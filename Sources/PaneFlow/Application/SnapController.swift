import AppKit
import PaneFlowCore
import PaneFlowSystem

/// Drives drag-to-edge snapping: feeds gestures into `SnapStateMachine` and performs its effects.
@MainActor
final class SnapController {
    private var machine: SnapStateMachine
    private let preview = SnapPreviewPanel()
    private let displays: DisplayManager
    private let geometry: WindowGeometryController
    private let restore: WindowRestoreManager
    private var dwellTimer: Timer?
    var onStatus: ((String) -> Void)?
    /// Observes committed snaps (used by the drag self-test to attribute a snap to PaneFlow).
    var onCommit: ((SnapZone) -> Void)?
    /// Called after a drag snap was applied successfully (starts Snap Assist).
    var onSnapped: ((WindowToken, SnapZone) -> Void)?

    init(displays: DisplayManager, geometry: WindowGeometryController, restore: WindowRestoreManager) {
        self.displays = displays
        self.geometry = geometry
        self.restore = restore
        machine = SnapStateMachine(detector: SnapZoneDetector(topology: displays.topology))
    }

    func topologyChanged(_ topology: DisplayTopology) {
        machine.detector.topology = topology
    }

    func handle(_ event: PointerGestureEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        let effects: [SnapEffect]
        switch event {
        case let .moveStarted(session, window, cursor):
            machine.detector.topology = displays.topology
            effects = machine.handle(.dragStarted(session: session, window: window.token, cursor: cursor, time: now))
        case let .moveCursor(point, time):
            effects = machine.handle(.cursorMoved(point, time: time))
        case .mouseReleased:
            effects = machine.handle(.mouseReleased)
        case .cancel:
            effects = machine.handle(.cancel)
        case let .suppression(on):
            effects = machine.handle(.suppression(on))
        default:
            return
        }
        perform(effects)
        updateDwellTimer()
    }

    private func perform(_ effects: [SnapEffect]) {
        for effect in effects {
            switch effect {
            case let .showPreview(zone):
                guard let frame = zone.frame(in: displays.topology) else { continue }
                preview.show(displays.converter.appKitRect(fromGlobal: frame))
            case .hidePreview:
                preview.hide()
            case let .commit(session, window, zone):
                onCommit?(zone)
                commit(session: session, window: window, zone: zone)
            }
        }
    }

    private func commit(session: SnapSessionID, window: WindowToken, zone: SnapZone) {
        guard let frame = zone.frame(in: displays.topology) else {
            _ = machine.handle(.commitFinished(session: session))
            return
        }
        Task {
            // Let the app finish its own drag loop first, or it may overwrite our position.
            try? await Task.sleep(for: .milliseconds(60))
            do {
                let result = try await geometry.apply(frame, to: window)
                restore.recordOriginal(result.previousFrame, for: window)
                onSnapped?(window, zone)
            } catch {
                onStatus?(ApplicationCoordinator.describe(error))
            }
            _ = machine.handle(.commitFinished(session: session))
            updateDwellTimer()
        }
    }

    /// Ticks only while a zone is waiting to dwell (shared edges), so there is no idle timer.
    private func updateDwellTimer() {
        if machine.state.needsDwellTimer {
            guard dwellTimer == nil else { return }
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.perform(self.machine.handle(.tick(time: ProcessInfo.processInfo.systemUptime)))
                    self.updateDwellTimer()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            dwellTimer = timer
        } else {
            dwellTimer?.invalidate()
            dwellTimer = nil
        }
    }
}
