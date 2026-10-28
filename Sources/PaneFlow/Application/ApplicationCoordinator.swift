import AppKit
import Carbon.HIToolbox
import PaneFlowCore
import PaneFlowSystem

/// Window placements available from the menu and keyboard shortcuts.
enum WindowCommand: Equatable {
    /// Snap to a region; `displayID` nil means the display the window is on.
    case snap(SnapRegion, displayID: UInt32? = nil)
    /// Windows-style ←/→: repeated presses walk across displays.
    case cycle(SnapCycling.Direction)
    case center
    case restore
    case nextDisplay
    /// Mirror the tiled windows around the focused one: left ↔ right (or top ↔ bottom).
    case swap

    var title: String {
        switch self {
        case let .snap(region, _): region.title
        case .cycle(.left): "Metade esquerda (trocar de monitor)"
        case .cycle(.right): "Metade direita (trocar de monitor)"
        case .center: "Centralizar"
        case .restore: "Restaurar janela"
        case .nextDisplay: "Mover para o próximo monitor"
        case .swap: "Inverter janelas (esquerda ↔ direita)"
        }
    }
}

extension SnapRegion {
    var title: String {
        switch self {
        case .leftHalf: "Metade esquerda"
        case .rightHalf: "Metade direita"
        case .topHalf: "Metade superior"
        case .bottomHalf: "Metade inferior"
        case .maximize: "Maximizar"
        case .topLeftQuarter: "Quarto superior esquerdo"
        case .topRightQuarter: "Quarto superior direito"
        case .bottomLeftQuarter: "Quarto inferior esquerdo"
        case .bottomRightQuarter: "Quarto inferior direito"
        }
    }
}

/// Owns the long-lived services and wires them together. Only object that knows about all layers.
@MainActor
final class ApplicationCoordinator {
    let permissions = PermissionManager()
    let displays = DisplayManager()
    let repository = WindowRepository()
    let restore = WindowRestoreManager()
    let preferences = Preferences()
    lazy var geometry = WindowGeometryController(repository: repository)
    private lazy var gestures = PointerGestureTracker(repository: repository)
    private lazy var snapping = SnapController(displays: displays, geometry: geometry, restore: restore)
    private lazy var assist = SnapAssistController(repository: repository, geometry: geometry, displays: displays, restore: restore)
    private lazy var linkedResize = LinkedResizeController(repository: repository, geometry: geometry) { [weak self] in
        self?.displays.topology ?? DisplayTopology(displays: [])
    }

    private let launchOptions: LaunchOptions
    private var menuBar: MenuBarController?
    private var permissionsWindow: PermissionsWindowController?
    private(set) var lastStatus: String?
    private(set) var shortcutConflicts: [String] = []
    private var commandInFlight = false
    /// Drag test only: lets one case exercise Snap Assist.
    private var assistEnabledForTest = false

    static let shortcuts: [(HotKeyCenter.Shortcut, WindowCommand)] = {
        let mods = controlKey | optionKey
        return [
            (.init(keyCode: kVK_LeftArrow, modifiers: mods, display: "⌃⌥←"), .cycle(.left)),
            (.init(keyCode: kVK_RightArrow, modifiers: mods, display: "⌃⌥→"), .cycle(.right)),
            (.init(keyCode: kVK_UpArrow, modifiers: mods, display: "⌃⌥↑"), .snap(.maximize)),
            (.init(keyCode: kVK_DownArrow, modifiers: mods, display: "⌃⌥↓"), .restore),
            (.init(keyCode: kVK_ANSI_C, modifiers: mods, display: "⌃⌥C"), .center),
            (.init(keyCode: kVK_Return, modifiers: mods, display: "⌃⌥↩"), .nextDisplay),
            (.init(keyCode: kVK_ANSI_S, modifiers: mods, display: "⌃⌥S"), .swap),
        ]
    }()

    var isEnabled: Bool {
        get { preferences.enabled }
        set {
            preferences.enabled = newValue
            refreshServices()
        }
    }

    init(launchOptions: LaunchOptions) {
        self.launchOptions = launchOptions
    }

    func start() {
        Log.lifecycle.notice("PaneFlow starting (accessibility: \(self.permissions.accessibilityGranted), screen recording: \(self.permissions.screenRecordingGranted))")
        permissions.onChange = { [weak self] kind, granted in
            guard let self else { return }
            if kind == .accessibility && !granted { self.lastStatus = "Acessibilidade revogada — controle de janelas pausado" }
            self.refreshServices()
        }
        displays.onChange = { [weak self] topology in
            self?.snapping.topologyChanged(topology)
            self?.menuBar?.rebuild()
        }
        gestures.onEvent = { [weak self] event in self?.route(event) }
        gestures.topologyProvider = { [weak self] in self?.displays.topology ?? DisplayTopology(displays: []) }
        snapping.onStatus = { [weak self] status in
            self?.lastStatus = status
            self?.menuBar?.rebuild()
        }
        snapping.onSnapped = { [weak self] window, zone in self?.offerAssist(after: window, zone: zone) }
        assist.onStatus = { [weak self] status in
            self?.lastStatus = status
            self?.menuBar?.rebuild()
        }
        assist.onRequestScreenRecording = { [weak self] in
            self?.permissions.request(.screenRecording)
            self?.showPermissions()
        }

        if launchOptions.runSelfTest {
            Task { await runSelfTest(terminateWhenDone: true) }
            return
        }
        if launchOptions.runDragTest {
            Task { await runDragTest() }
            return
        }
        menuBar = MenuBarController(coordinator: self)
        refreshServices()
        if !permissions.accessibilityGranted {
            showPermissions()
        }
    }

    /// Starts or stops each feature according to permissions and preferences.
    func refreshServices() {
        let active = permissions.accessibilityGranted && preferences.enabled
        gestures.edgeResistanceEnabled = preferences.snapOnDrag && preferences.edgeResistance
        if active && (preferences.snapOnDrag || preferences.linkedResize) {
            gestures.start()
        } else if gestures.isRunning {
            gestures.stop()
        }

        HotKeyCenter.shared.unregisterAll()
        shortcutConflicts = []
        if active && preferences.keyboardShortcuts {
            for (shortcut, command) in Self.shortcuts {
                do {
                    try HotKeyCenter.shared.register(shortcut) { [weak self] in self?.perform(command) }
                } catch {
                    shortcutConflicts.append(shortcut.display)
                    Log.errors.error("Shortcut \(shortcut.display, privacy: .public) unavailable: \(String(describing: error), privacy: .public)")
                }
            }
        }
        menuBar?.rebuild()
    }

    private func route(_ event: PointerGestureEvent) {
        switch event {
        case let .resizeStarted(session, driver, original, servers):
            if preferences.linkedResize || launchOptions.runDragTest { linkedResize.begin(session: session, driver: driver, original: original, serverWindows: servers) }
        case let .resizeFrame(session, current):
            linkedResize.update(session: session, current: current)
        case let .resizeEnded(session, final):
            linkedResize.end(session: session, final: final)
        default:
            if preferences.snapOnDrag || launchOptions.runDragTest { snapping.handle(event) }
        }
    }

    // MARK: Commands

    func perform(_ command: WindowCommand) {
        guard isEnabled, permissions.accessibilityGranted else {
            showPermissions()
            return
        }
        // One command at a time: a second request while an app is slow to respond is ignored, not queued.
        guard !commandInFlight else { return }
        commandInFlight = true
        Task {
            defer { commandInFlight = false }
            await execute(command)
            menuBar?.rebuild()
        }
    }

    private func execute(_ command: WindowCommand) async {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() else {
            lastStatus = "Nenhuma janela ativa"
            return
        }
        let app = RunningApplicationInfo(
            pid: front.processIdentifier, bundleIdentifier: front.bundleIdentifier,
            name: front.localizedName ?? "App", isHidden: front.isHidden
        )
        do {
            let window = try await repository.focusedWindow(of: app)
            if command == .swap {
                await swap(around: window)
                return
            }
            guard let target = targetFrame(for: command, window: window) else {
                lastStatus = switch command {
                case .restore: "Nada para restaurar"
                case .cycle: "Não há monitor nessa direção"
                default: "Nenhum monitor disponível"
                }
                return
            }
            let result = try await geometry.apply(target, to: window.token)
            if command == .restore {
                restore.clear(window.token)
            } else {
                restore.recordOriginal(result.previousFrame, for: window.token)
            }
            if result.verdict.isAcceptable, let zone = snappedZone(for: command, window: window) {
                offerAssist(after: window.token, zone: zone)
            }
            lastStatus = switch result.verdict {
            case .exact: "\(command.title): feito"
            case .adjustedByApplication: "\(command.title): o app ajustou o tamanho"
            case .failed: "\(command.title): falhou"
            }
        } catch let error as GeometryOperationError {
            lastStatus = Self.describe(error)
        } catch {
            lastStatus = "Não foi possível ler a janela ativa"
            Log.errors.error("Focused window lookup failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func offerAssist(after window: WindowToken, zone: SnapZone) {
        guard launchOptions.runDragTest ? assistEnabledForTest : preferences.snapAssist else { return }
        assist.begin(after: window, zone: zone)
    }

    /// The zone a snapping command placed the window in (for Snap Assist).
    private func snappedZone(for command: WindowCommand, window: WindowSnapshot) -> SnapZone? {
        let topology = displays.topology
        switch command {
        case let .snap(region, displayID):
            guard let id = displayID ?? topology.display(for: window.frame)?.id else { return nil }
            return SnapZone(region: region, displayID: id)
        case let .cycle(direction):
            return SnapCycling.target(direction: direction, windowFrame: window.frame, topology: topology)
        default:
            return nil
        }
    }

    /// Mirrors the windows tiled together with `window` on its display. Applied as a compensated
    /// transaction: if one window refuses, the ones already moved are put back.
    func swap(around window: WindowSnapshot) async {
        guard let display = displays.topology.display(for: window.frame) else { return }
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid() }
            .map { RunningApplicationInfo(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier,
                                          name: $0.localizedName ?? "App", isHidden: $0.isHidden) }
        let policy = WindowEligibilityPolicy(ownProcessID: getpid())
        let windows = await repository.discoverWindows(of: apps).filter { candidate in
            guard candidate.isOnScreen || candidate.token == window.token,
                  case .eligible(resizable: true) = policy.evaluate(candidate),
                  display.frame.intersects(candidate.frame) else { return false }
            return true
        }
        let candidates = windows.map { LinkedResize.Candidate(token: $0.token, frame: $0.frame) }
        let group = TileArrangement.connectedGroup(from: window.token, windows: candidates)
        guard !group.isEmpty else {
            lastStatus = "Nenhuma janela para inverter"
            return
        }
        let targets = TileArrangement.mirrored(group, in: display.visibleFrame, axis: TileArrangement.swapAxis(for: group))
        var applied: [(WindowToken, CGRect)] = []
        for member in group {
            guard let target = targets[member.token] else { continue }
            do {
                let result = try await geometry.apply(target, to: member.token)
                applied.append((member.token, result.previousFrame))
            } catch {
                for (token, previous) in applied.reversed() { _ = try? await geometry.apply(previous, to: token) }
                lastStatus = "Não foi possível inverter: \(Self.describe(error).lowercased())"
                Log.snapGroups.error("Swap rolled back after a failure")
                return
            }
        }
        lastStatus = group.count == 1 ? "Janela espelhada" : "\(group.count) janelas invertidas"
    }

    private func targetFrame(for command: WindowCommand, window: WindowSnapshot) -> CGRect? {
        let topology = displays.topology
        guard let display = topology.display(for: window.frame) else { return nil }
        switch command {
        case let .snap(region, displayID):
            let target = displayID.flatMap(topology.display(withID:)) ?? display
            return region.frame(in: target.visibleFrame)
        case let .cycle(direction):
            return SnapCycling.target(direction: direction, windowFrame: window.frame, topology: topology)?.frame(in: topology)
        case .center:
            return LayoutEngine.centered(size: window.frame.size, in: display.visibleFrame)
        case .restore:
            return restore.original(for: window.token)
        case .nextDisplay:
            guard let next = topology.display(after: display.id) else { return nil }
            // Keep the window's relative position and size within the usable area.
            let from = display.visibleFrame, to = next.visibleFrame
            let sx = to.width / from.width, sy = to.height / from.height
            let size = CGSize(width: min(window.frame.width * sx, to.width), height: min(window.frame.height * sy, to.height))
            var frame = CGRect(
                origin: CGPoint(x: to.minX + (window.frame.minX - from.minX) * sx, y: to.minY + (window.frame.minY - from.minY) * sy),
                size: size
            )
            frame.origin.x = min(max(frame.minX, to.minX), to.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, to.minY), to.maxY - frame.height)
            return frame
        case .swap:
            return nil
        }
    }

    static func describe(_ error: Error) -> String {
        guard let error = error as? GeometryOperationError else { return "A operação falhou" }
        return switch error {
        case .processTerminated: "O app foi encerrado"
        case .windowGone: "A janela foi fechada"
        case .ineligible: "Esta janela não pode ser organizada"
        case .notMovable: "Esta janela não pode ser movida"
        case .notResizable: "Esta janela não pode ser redimensionada"
        case .applicationUnresponsive: "O app não está respondendo"
        case .accessibility: "A solicitação de Acessibilidade falhou"
        case .verificationFailed: "O app recusou o novo tamanho/posição"
        }
    }

    // MARK: Windows

    func showPermissions() {
        if permissionsWindow == nil {
            permissionsWindow = PermissionsWindowController(permissions: permissions)
        }
        permissionsWindow?.present()
    }

    // MARK: Diagnostics

    func runSelfTest(terminateWhenDone: Bool) async {
        let test = Phase1SelfTest(
            repository: repository, geometry: geometry, topology: displays.topology,
            accessibilityGranted: permissions.accessibilityGranted,
            restoreAfterwards: !launchOptions.keepSelfTestLayout
        )
        let report = await test.run()
        var written: URL?
        do {
            if let output = launchOptions.selfTestOutput {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(report).write(to: output, options: .atomic)
                written = output
            } else {
                written = try DiagnosticsReport.write(report, named: "selftest")
            }
        } catch {
            Log.errors.error("Could not write self-test report: \(error.localizedDescription, privacy: .public)")
        }
        lastStatus = "Autoteste: \(report.passed ? "APROVADO" : "FALHOU") (\(report.checks.filter(\.passed).count)/\(report.checks.count))"
        Log.lifecycle.notice("\(self.lastStatus ?? "", privacy: .public) → \(written?.path ?? "-", privacy: .public)")
        if terminateWhenDone {
            NSApp.terminate(nil)
        } else {
            menuBar?.rebuild()
            if let written { NSWorkspace.shared.activateFileViewerSelecting([written]) }
        }
    }

    private func runDragTest() async {
        guard permissions.accessibilityGranted else {
            writeReport(DragSelfTest.Report(nativeEdgeTilingEnabled: nil, checks: [.init(name: "accessibility", passed: false, detail: "not granted")]))
            NSApp.terminate(nil)
            return
        }
        var commits: [SnapZone] = []
        snapping.onCommit = { commits.append($0) }
        gestures.start()
        let test = DragSelfTest(
            repository: repository, geometry: geometry, topology: displays.topology,
            commits: { commits }, resetCommits: { commits.removeAll() },
            setAssistEnabled: { [weak self] in self?.assistEnabledForTest = $0 },
            assistState: { [weak self] in (self?.assist.isShowing ?? false, self?.assist.visibleCandidateCount ?? 0) },
            assistSelection: { [weak self] in self?.assist.selectedCandidate },
            swap: { [weak self] window in await self?.swap(around: window) }
        )
        let report = await test.run()
        gestures.stop()
        try? await Task.sleep(for: .milliseconds(800)) // let deferred frame restores finish
        writeReport(report)
        Log.lifecycle.notice("Drag test: \(report.passed ? "PASSED" : "FAILED", privacy: .public)")
        NSApp.terminate(nil)
    }

    private func writeReport<T: Encodable>(_ report: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let output = launchOptions.selfTestOutput {
            try? encoder.encode(report).write(to: output, options: .atomic)
        } else {
            _ = try? DiagnosticsReport.write(report, named: "dragtest")
        }
    }

    func exportDiagnostics() {
        let report = DiagnosticsReport(
            permissions: [
                PermissionKind.accessibility.rawValue: permissions.accessibilityGranted,
                PermissionKind.screenRecording.rawValue: permissions.screenRecordingGranted,
            ],
            displays: displays.topology.displays.map {
                .init(frame: NSStringFromRect($0.frame), visibleFrame: NSStringFromRect($0.visibleFrame),
                      scale: $0.scale, isPrimary: $0.isPrimary)
            },
            nativeWindowManager: .read(),
            notes: (lastStatus.map { ["lastStatus: \($0)"] } ?? []) + shortcutConflicts.map { "shortcutConflict: \($0)" }
        )
        do {
            let url = try DiagnosticsReport.write(report, named: "diagnostics")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            lastStatus = "Não foi possível exportar o diagnóstico"
        }
    }
}
