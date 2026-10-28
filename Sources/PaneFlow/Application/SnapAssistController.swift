import AppKit
import PaneFlowCore
import PaneFlowSystem

/// After a snap, offers the remaining empty regions one at a time with a picker of other windows.
@MainActor
final class SnapAssistController {
    private let repository: WindowRepository
    private let geometry: WindowGeometryController
    private let displays: DisplayManager
    private let restore: WindowRestoreManager
    private let policy = WindowEligibilityPolicy(ownProcessID: getpid())

    var onStatus: ((String) -> Void)?
    var onRequestScreenRecording: (() -> Void)?

    private var generation = 0
    private var pending: [SnapZone] = []
    private var placed: Set<WindowToken> = []
    private var panel: SnapAssistPanelController?
    private var captureTask: Task<Void, Never>?
    private var dismissMonitors: [Any] = []
    private var activationObserver: NSObjectProtocol?

    var isShowing: Bool { panel != nil }
    var visibleCandidateCount: Int { panel?.model.items.count ?? 0 }
    /// Token of the highlighted candidate (drag self-test).
    var selectedCandidate: WindowToken? {
        guard let model = panel?.model, let index = model.selection, model.filtered.indices.contains(index) else { return nil }
        return model.filtered[index].token
    }

    init(repository: WindowRepository, geometry: WindowGeometryController, displays: DisplayManager, restore: WindowRestoreManager) {
        self.repository = repository
        self.geometry = geometry
        self.displays = displays
        self.restore = restore
    }

    /// Starts an assist session after `window` was snapped into `zone`.
    func begin(after window: WindowToken, zone: SnapZone) {
        cancel()
        generation += 1
        let current = generation
        let clock = ContinuousClock(), start = clock.now
        Task {
            let windows = await discover()
            guard current == generation, let display = displays.topology.display(withID: zone.displayID) else { return }
            let onDisplay = windows.filter { $0.token != window && display.frame.intersects($0.frame) }.map(\.frame)
            let regions = SnapAssistPlanner.emptyRegions(after: zone.region, in: display.visibleFrame, occupied: onDisplay)
            pending = regions.map { SnapZone(region: $0, displayID: zone.displayID) }
            placed = [window]
            await showNext(using: windows)
            PerformanceMonitor.shared.record("snapAssist.open", milliseconds: (clock.now - start).milliseconds)
        }
    }

    func cancel() {
        generation += 1
        captureTask?.cancel()
        captureTask = nil
        closePanel()
        pending = []
    }

    private func closePanel() {
        dismissMonitors.forEach(NSEvent.removeMonitor)
        dismissMonitors.removeAll()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        panel?.close()
        panel = nil
    }

    /// Closes the picker when the user clicks anywhere outside it or switches to another app.
    private func watchForDismissal() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let frame = self.panel?.frame else { return }
                if !frame.contains(NSEvent.mouseLocation) { self.cancel() }
            }
        }) {
            dismissMonitors.append(monitor)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                // System alerts come from background agents; only a real app switch dismisses.
                if app?.activationPolicy == .regular, app?.processIdentifier != getpid() { self?.cancel() }
            }
        }
    }

    private func discover() async -> [WindowSnapshot] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid() }
            .map { RunningApplicationInfo(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier,
                                          name: $0.localizedName ?? "App", isHidden: $0.isHidden) }
        return await repository.discoverWindows(of: apps)
    }

    private func candidates(from windows: [WindowSnapshot]) -> [WindowSnapshot] {
        windows.filter { window in
            guard window.isOnScreen, !placed.contains(window.token),
                  case .eligible(resizable: true) = policy.evaluate(window) else { return false }
            return true
        }
    }

    /// Exact empty space for `zone`: measured against the *actual* frames of the windows already
    /// placed in this layout, so the next window neither leaves a hole nor overlaps.
    private func fillFrame(for zone: SnapZone) async -> CGRect? {
        guard let display = displays.topology.display(withID: zone.displayID) else { return nil }
        let placedFrames = await repository.frames(of: Array(placed))
        let onDisplay = placedFrames.values.filter { display.frame.intersects($0) }
        let frame = SnapAssistPlanner.fillFrame(for: zone.region, in: display.visibleFrame, placed: Array(onDisplay))
        return frame.width >= 120 && frame.height >= 120 ? frame : nil
    }

    private func showNext(using windows: [WindowSnapshot]) async {
        closePanel()
        captureTask?.cancel()
        let list = candidates(from: windows)
        let current = generation
        guard let zone = pending.first, !list.isEmpty, let frame = await fillFrame(for: zone), current == generation else {
            pending = []
            return
        }

        // Label windows of the same app ("2 de 3") so documents can be told apart.
        let counts = Dictionary(grouping: list, by: \.pid).mapValues(\.count)
        var seen: [pid_t: Int] = [:]
        let items = list.map { window -> AssistItem in
            seen[window.pid, default: 0] += 1
            let count = counts[window.pid] ?? 1
            return AssistItem(
                token: window.token, windowID: window.windowID, pid: window.pid, appName: window.applicationName,
                title: window.title, siblingLabel: count > 1 ? "\(seen[window.pid]!) de \(count)" : nil,
                aspectRatio: window.frame.height > 0 ? window.frame.width / window.frame.height : 1.5
            )
        }

        let model = SnapAssistViewModel(items: items, regionTitle: zone.region.title,
                                        showsCaptureHint: !WindowThumbnailService.isAuthorized)
        model.onCancel = { [weak self] in self?.cancel() }
        model.onChoose = { [weak self] item in self?.choose(item, into: frame, zone: zone) }
        model.onEnableThumbnails = { [weak self] in
            self?.cancel()
            self?.onRequestScreenRecording?()
        }
        let controller = SnapAssistPanelController(frame: displays.converter.appKitRect(fromGlobal: frame), model: model)
        panel = controller
        controller.show()
        watchForDismissal()
        Log.snapAssist.info("Snap Assist showing \(items.count) candidate(s)")

        // Thumbnails for unambiguously identified windows only; others keep the icon placeholder.
        let ids = items.compactMap { item in item.windowID.map { (item.token, $0) } }
        let tokensByID = Dictionary(ids.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        captureTask = Task { [weak model] in
            await WindowThumbnailService.shared.capture(windowIDs: ids.map(\.1)) { id, image in
                guard let model, let token = tokensByID[id] else { return }
                model.thumbnails[token] = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    private func choose(_ item: AssistItem, into frame: CGRect, zone: SnapZone) {
        let current = generation
        closePanel()
        captureTask?.cancel()
        Task {
            do {
                let result = try await geometry.apply(frame, to: item.token)
                restore.recordOriginal(result.previousFrame, for: item.token)
                await fixOverflow(item.token, target: frame, actual: result.actualFrame, zone: zone)
                placed.insert(item.token)
                await focus(item)
            } catch {
                onStatus?(ApplicationCoordinator.describe(error))
            }
            guard current == generation else { return }
            pending.removeFirst()
            guard !pending.isEmpty else { return }
            await showNext(using: await discover())
        }
    }

    /// The chosen app may refuse to be as small as the empty space (minimum size). Then it is kept
    /// on screen against the outer edge and the placed neighbours are trimmed so nothing overlaps.
    private func fixOverflow(_ token: WindowToken, target: CGRect, actual: CGRect, zone: SnapZone) async {
        guard let display = displays.topology.display(withID: zone.displayID) else { return }
        let neighbours = await repository.frames(of: Array(placed))
        guard let fix = SnapAssistPlanner.resolveOverflow(target: target, actual: actual, area: display.visibleFrame,
                                                          neighbours: neighbours) else { return }
        _ = try? await geometry.apply(fix.chosen, to: token)
        var refused = false
        for (neighbour, frame) in fix.neighbours {
            let result = try? await geometry.apply(frame, to: neighbour)
            if result?.actualFrame.intersectionArea(with: fix.chosen) ?? 1 > 1 { refused = true }
        }
        Log.snapAssist.info("Chosen window larger than the empty space; neighbours trimmed (refused: \(refused))")
        if refused { onStatus?("Um dos apps exige um tamanho mínimo maior que o espaço disponível") }
    }

    /// Brings the chosen window forward so the user can start working in it.
    private func focus(_ item: AssistItem) async {
        if let element = repository.element(for: item.token) {
            _ = await AccessibilityExecutor.shared.perform { (try? element.perform(kAXRaiseAction)) != nil }
        }
        NSRunningApplication(processIdentifier: item.pid)?.activate()
    }
}
