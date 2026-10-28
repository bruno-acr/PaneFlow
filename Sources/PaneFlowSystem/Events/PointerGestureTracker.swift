import AppKit
import PaneFlowCore

/// What a mouse gesture turned out to be.
public enum PointerGestureEvent: Sendable {
    /// A window started moving with the cursor (title-bar drag).
    case moveStarted(session: SnapSessionID, window: WindowSnapshot, cursor: CGPoint)
    case moveCursor(CGPoint, time: TimeInterval)
    /// A window started changing size (edge/corner drag).
    case resizeStarted(session: SnapSessionID, driver: WindowSnapshot, original: CGRect, serverWindows: [ServerWindowSignal])
    case resizeFrame(session: SnapSessionID, current: CGRect)
    case resizeEnded(session: SnapSessionID, final: CGRect)
    case mouseReleased(session: SnapSessionID)
    case cancel
    case suppression(Bool)
}

/// Classifies global mouse gestures into window moves and window resizes **by observing geometry**.
///
/// macOS has no "window X is being dragged" event. On mouse-down PaneFlow notes the windows under
/// the cursor (window server list, then Accessibility); while the mouse is dragged it re-reads their
/// frames. A window whose origin changes with a constant size is being moved; one whose size changes
/// is being resized. If nothing changes after a short distance the gesture is content (text selection,
/// file drag, tab drag…) and tracking stops — content drags can never trigger a snap.
///
/// Measured on macOS 27: while a window is moved by its title bar the window server runs the drag
/// itself and **no `leftMouseDragged`/`leftMouseUp` reaches global monitors** (resizes do deliver
/// them), and the app's Accessibility position lags behind the cursor. So while the button is held
/// over a window, the cursor, button state and Escape key are *sampled* at 60 Hz, and window bounds
/// are read from the window server (`CGWindowListCreateDescriptionFromArray`, no IPC to the app).
/// Sampling exists only between a mouse-down on a window and its release; there is no idle polling.
@MainActor
public final class PointerGestureTracker {
    public var onEvent: ((PointerGestureEvent) -> Void)?
    /// Holding these modifiers suppresses snapping for the current drag.
    public var suppressionModifiers: NSEvent.ModifierFlags = [.option]
    /// Hold the cursor at edges shared between displays while a window is moved (see `EdgeResistance`).
    public var edgeResistanceEnabled = true
    public var topologyProvider: (() -> DisplayTopology)?
    private var resistance = EdgeResistance()
    private let resistanceSource = CGEventSource(stateID: .hidSystemState)

    private let repository: WindowRepository
    private var monitors: [Any] = []

    private enum Phase {
        case idle
        case resolving
        case undetermined
        case moving(WindowToken)
        case resizing(WindowToken)
        case content
    }

    private var phase: Phase = .idle
    private var session: SnapSessionID = 0
    private var downPoint: CGPoint = .zero
    private var lastCursor: CGPoint = .zero
    private var tracked: [WindowToken: WindowSnapshot] = [:]
    /// Frames captured by the window server at mouse-down, before anything moved.
    private var originals: [WindowToken: CGRect] = [:]
    /// Window-server ids of the tracked windows, for cheap bounds reads while dragging.
    private var serverIDs: [WindowToken: UInt32] = [:]
    private var downTime: TimeInterval = 0
    private var loggedContent = false
    private var serverWindows: [ServerWindowSignal] = []
    private var readInFlight = false
    private var undeterminedReads = 0
    private var suppressed = false
    private var sampler: Timer?
    private var escapeWasDown = false

    /// Hit slop around window frames: macOS resize handles extend a few points outside the frame.
    private let edgeSlop: CGFloat = 10
    private let moveThreshold: CGFloat = 3

    public init(repository: WindowRepository) {
        self.repository = repository
    }

    public var isRunning: Bool { !monitors.isEmpty }

    public func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged, .keyDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            // Global monitors are delivered on the main thread.
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(monitor)
        }
        Log.snapDetection.info("Pointer gesture tracking started")
    }

    public func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
        Log.snapDetection.info("Pointer gesture tracking stopped")
    }

    private func reset() {
        sampler?.invalidate()
        sampler = nil
        escapeWasDown = false
        phase = .idle
        tracked = [:]
        originals = [:]
        serverIDs = [:]
        loggedContent = false
        serverWindows = []
        readInFlight = false
        undeterminedReads = 0
    }

    /// Cursor in global (CG) coordinates. `CGEvent.location` already uses them.
    private func cursor(of event: NSEvent) -> CGPoint {
        event.cgEvent?.location ?? .zero
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: mouseDown(at: cursor(of: event), modifiers: event.modifierFlags)
        case .leftMouseDragged: mouseDragged(to: cursor(of: event), modifiers: event.modifierFlags)
        case .leftMouseUp: mouseUp(at: cursor(of: event))
        case .flagsChanged: updateSuppression(event.modifierFlags)
        case .keyDown where event.keyCode == 53: // Escape (sampled too, see `sample()`)
            if case .moving = phase, !escapeWasDown { escapeWasDown = true; onEvent?(.cancel) }
        default: break
        }
    }

    private func mouseDown(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        reset()
        session &+= 1
        downPoint = point
        lastCursor = point
        downTime = ProcessInfo.processInfo.systemUptime
        suppressed = !modifiers.intersection(suppressionModifiers).isEmpty

        let ownPID = getpid()
        let windows = WindowRepository.onScreenServerWindows().filter { $0.layer == 0 && $0.pid != ownPID }
        // Frontmost window containing the cursor (move candidate) plus any window whose edge is under it.
        let hits = windows.filter { $0.frame.insetBy(dx: -edgeSlop, dy: -edgeSlop).contains(point) }
        guard !hits.isEmpty else { return }
        let front = hits[0]
        var candidates = [front]
        if !front.frame.insetBy(dx: edgeSlop, dy: edgeSlop).contains(point) {
            // On or near an edge: the neighbour behind the edge may be the one actually resized.
            candidates += hits.dropFirst().prefix(2)
        }
        serverWindows = windows
        phase = .resolving
        startSampling()

        let current = session
        let apps = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications
            .filter { app in candidates.contains { $0.pid == app.processIdentifier } }
            .map { ($0.processIdentifier, RunningApplicationInfo(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier,
                                                                 name: $0.localizedName ?? "?", isHidden: $0.isHidden)) })
        Task { [weak self, repository] in
            var resolved: [WindowToken: WindowSnapshot] = [:]
            var downFrames: [WindowToken: CGRect] = [:]
            var ids: [WindowToken: UInt32] = [:]
            for candidate in candidates {
                guard let app = apps[candidate.pid], let snapshot = await repository.resolve(candidate, app: app) else { continue }
                resolved[snapshot.token] = snapshot
                downFrames[snapshot.token] = candidate.frame
                ids[snapshot.token] = candidate.windowID
            }
            guard let self, self.session == current, case .resolving = self.phase else { return }
            self.tracked = resolved
            self.originals = downFrames
            self.serverIDs = ids
            self.phase = resolved.isEmpty ? .content : .undetermined
            if !resolved.isEmpty { self.mouseDragged(to: self.lastCursor, modifiers: []) }
        }
    }

    private func startSampling() {
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        sampler = timer
    }

    private func sample() {
        let point = CGEvent(source: nil)?.location ?? lastCursor
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            mouseUp(at: point)
            return
        }
        updateSuppression(NSEvent.modifierFlags)
        let escapeDown = CGEventSource.keyState(.combinedSessionState, key: 53)
        if escapeDown && !escapeWasDown, case .moving = phase { onEvent?(.cancel) }
        escapeWasDown = escapeDown
        if case .moving = phase, edgeResistanceEnabled, !suppressed, let topology = topologyProvider?(),
           let held = resistance.filter(point, topology: topology) {
            // Put the cursor (and the window the window server is dragging) back on the shared edge.
            CGEvent(mouseEventSource: resistanceSource, mouseType: .leftMouseDragged, mouseCursorPosition: held,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
            if held != lastCursor { mouseDragged(to: held, modifiers: []) }
            return
        }
        switch phase {
        case .undetermined, .content:
            // Window-server reads are cheap: keep checking every tick while the button is held, so a
            // window that starts moving late (or whose app reports late) is never missed.
            lastCursor = point
            classify(Self.serverFrames(for: serverIDs))
        default:
            if point != lastCursor { mouseDragged(to: point, modifiers: []) }
        }
    }

    private func mouseDragged(to point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        lastCursor = point
        switch phase {
        case .moving:
            onEvent?(.moveCursor(point, time: ProcessInfo.processInfo.systemUptime))
        case .undetermined, .content, .resizing:
            readFrames()
        default:
            break
        }
    }

    private static func serverFrames(for ids: [WindowToken: UInt32]) -> [WindowToken: CGRect] {
        let frames = WindowRepository.serverFrames(of: Array(ids.values))
        return ids.reduce(into: [:]) { result, entry in result[entry.key] = frames[entry.value] }
    }

    /// Window-server bounds when available; otherwise one coalesced Accessibility read (at most one
    /// in flight, so a slow app never builds up a queue).
    private func readFrames() {
        let tokens: [WindowToken]
        switch phase {
        case .undetermined, .content: tokens = Array(tracked.keys)
        case let .resizing(driver): tokens = [driver]
        default: return
        }
        let server = Self.serverFrames(for: serverIDs.filter { tokens.contains($0.key) })
        if server.count == tokens.count {
            classify(server)
            return
        }
        guard !readInFlight else { return }
        readInFlight = true
        let current = session
        Task { [weak self, repository] in
            let frames = await repository.frames(of: tokens)
            guard let self, self.session == current else { return }
            self.readInFlight = false
            self.classify(frames)
        }
    }

    private func classify(_ frames: [WindowToken: CGRect]) {
        switch phase {
        case .undetermined, .content:
            // Resize wins over move: dragging a left/top edge changes the origin too.
            for (token, frame) in frames {
                guard let original = originals[token] else { continue }
                if abs(frame.width - original.width) > 0.5 || abs(frame.height - original.height) > 0.5 {
                    phase = .resizing(token)
                    Log.snapDetection.debug("Gesture classified as resize")
                    onEvent?(.resizeStarted(session: session, driver: tracked[token]!, original: original, serverWindows: serverWindows))
                    onEvent?(.resizeFrame(session: session, current: frame))
                    return
                }
            }
            for (token, frame) in frames {
                guard let original = originals[token] else { continue }
                if hypot(frame.minX - original.minX, frame.minY - original.minY) > moveThreshold {
                    phase = .moving(token)
                    if let topology = topologyProvider?() { resistance.begin(at: downPoint, topology: topology) }
                    Log.snapDetection.debug("Gesture classified as window move")
                    onEvent?(.moveStarted(session: session, window: tracked[token]!, cursor: lastCursor))
                    if suppressed { onEvent?(.suppression(true)) }
                    return
                }
            }
            undeterminedReads += 1
            let held = ProcessInfo.processInfo.systemUptime - downTime
            if !loggedContent, held > 0.5, hypot(lastCursor.x - downPoint.x, lastCursor.y - downPoint.y) > 150 {
                // Still watched (cheaply) until release; a late window move is still recognised.
                phase = .content
                loggedContent = true
                Log.snapDetection.debug("Gesture looks like a content drag")
            }
        case let .resizing(driver):
            if let frame = frames[driver] { onEvent?(.resizeFrame(session: session, current: frame)) }
        default:
            break
        }
    }

    private func mouseUp(at point: CGPoint) {
        lastCursor = point
        let ended = session
        switch phase {
        case .moving:
            onEvent?(.moveCursor(point, time: ProcessInfo.processInfo.systemUptime))
            onEvent?(.mouseReleased(session: ended))
            reset()
        case let .resizing(driver):
            reset()
            Task { [weak self, repository] in
                // Read after the app has processed the final mouse-up.
                try? await Task.sleep(for: .milliseconds(40))
                if let frame = await repository.frames(of: [driver])[driver] { // app's final, settled size
                    self?.onEvent?(.resizeEnded(session: ended, final: frame))
                }
            }
        default:
            reset()
        }
    }

    private func updateSuppression(_ flags: NSEvent.ModifierFlags) {
        let now = !flags.intersection(suppressionModifiers).isEmpty
        guard now != suppressed else { return }
        suppressed = now
        if case .moving = phase { onEvent?(.suppression(now)) }
    }
}
