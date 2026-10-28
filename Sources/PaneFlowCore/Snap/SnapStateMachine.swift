import CoreGraphics
import Foundation

/// Identifies one drag gesture. Results tagged with an older session are discarded.
public typealias SnapSessionID = UInt64

public enum SnapState: Sendable, Equatable {
    case idle
    case trackingDrag(session: SnapSessionID, window: WindowToken)
    /// Cursor is in a zone that needs to dwell before previewing (shared edges, activation delay).
    case candidate(session: SnapSessionID, window: WindowToken, zone: ZoneCandidate, since: TimeInterval)
    case previewing(session: SnapSessionID, window: WindowToken, zone: ZoneCandidate)
    case committing(session: SnapSessionID, window: WindowToken, zone: SnapZone)
    /// User cancelled (Escape); stays here until the mouse is released.
    case cancelled(session: SnapSessionID)

    public var session: SnapSessionID? {
        switch self {
        case .idle: nil
        case let .trackingDrag(s, _), let .candidate(s, _, _, _), let .previewing(s, _, _),
             let .committing(s, _, _), let .cancelled(s): s
        }
    }

    public var needsDwellTimer: Bool {
        if case .candidate = self { true } else { false }
    }
}

public enum SnapEvent: Sendable, Equatable {
    /// A window started moving under the cursor (detected by geometry, not by a click alone).
    case dragStarted(session: SnapSessionID, window: WindowToken, cursor: CGPoint, time: TimeInterval)
    case cursorMoved(CGPoint, time: TimeInterval)
    /// Periodic tick while a candidate is waiting to dwell.
    case tick(time: TimeInterval)
    case mouseReleased
    case cancel
    /// The suppression modifier was pressed (true) or released (false).
    case suppression(Bool)
    case commitFinished(session: SnapSessionID)
}

public enum SnapEffect: Sendable, Equatable {
    case showPreview(SnapZone)
    case hidePreview
    case commit(session: SnapSessionID, window: WindowToken, zone: SnapZone)
}

public struct SnapTiming: Sendable, Equatable, Codable {
    /// Dwell before an outer-edge zone previews.
    public var activationDelay: TimeInterval = 0
    /// Dwell before a shared-edge zone previews.
    public var sharedEdgeDelay: TimeInterval = 0.2

    public init(activationDelay: TimeInterval = 0, sharedEdgeDelay: TimeInterval = 0.2) {
        self.activationDelay = activationDelay
        self.sharedEdgeDelay = sharedEdgeDelay
    }
}

/// Deterministic, side-effect-free snap state machine. Time is injected, so every transition is unit-testable.
public struct SnapStateMachine: Sendable {
    public private(set) var state: SnapState = .idle
    public var detector: SnapZoneDetector
    public var timing: SnapTiming
    public private(set) var suppressed = false
    private var lastCursor: CGPoint?
    /// Display the cursor was last well inside of (outside every shared-edge band).
    public private(set) var approachDisplay: UInt32?

    public init(detector: SnapZoneDetector, timing: SnapTiming = SnapTiming()) {
        self.detector = detector
        self.timing = timing
    }

    public mutating func handle(_ event: SnapEvent) -> [SnapEffect] {
        switch (state, event) {
        case (.idle, let .dragStarted(session, window, cursor, time)):
            state = .trackingDrag(session: session, window: window)
            approachDisplay = detector.topology.display(containing: cursor)?.id
            return evaluate(cursor: cursor, time: time)

        case (.committing, .dragStarted):
            // A commit is in flight: never run two snaps at once.
            return []

        case (_, let .dragStarted(session, window, cursor, time)):
            // A new gesture supersedes a stale one (e.g. a missed mouse-up).
            let hide = isPreviewing ? [SnapEffect.hidePreview] : []
            state = .trackingDrag(session: session, window: window)
            approachDisplay = detector.topology.display(containing: cursor)?.id
            return hide + evaluate(cursor: cursor, time: time)

        case (.trackingDrag, let .cursorMoved(p, t)), (.candidate, let .cursorMoved(p, t)), (.previewing, let .cursorMoved(p, t)):
            return evaluate(cursor: p, time: t)

        case (let .candidate(session, window, zone, since), let .tick(t)):
            if t - since >= delay(for: zone) {
                state = .previewing(session: session, window: window, zone: zone)
                return [.showPreview(zone.zone)]
            }
            return []

        case (let .previewing(session, window, zone), .mouseReleased):
            state = .committing(session: session, window: window, zone: zone.zone)
            return [.hidePreview, .commit(session: session, window: window, zone: zone.zone)]

        case (.committing, .mouseReleased):
            return []

        case (_, .mouseReleased):
            let hide = isPreviewing ? [SnapEffect.hidePreview] : []
            state = .idle
            return hide

        case (.trackingDrag(let s, _), .cancel), (.candidate(let s, _, _, _), .cancel), (.previewing(let s, _, _), .cancel):
            let hide = isPreviewing ? [SnapEffect.hidePreview] : []
            state = .cancelled(session: s)
            return hide

        case (_, let .suppression(on)):
            suppressed = on
            guard let cursor = lastCursor else { return [] }
            switch state {
            case .trackingDrag, .candidate, .previewing: return evaluate(cursor: cursor, time: nil)
            default: return []
            }

        case (let .committing(session, _, _), let .commitFinished(finished)) where session == finished:
            state = .idle
            return []

        default:
            // Includes stale commitFinished, ticks outside candidate, events while cancelled/idle.
            return []
        }
    }

    private var isPreviewing: Bool {
        if case .previewing = state { true } else { false }
    }

    private func delay(for candidate: ZoneCandidate) -> TimeInterval {
        candidate.onSharedEdge ? max(timing.sharedEdgeDelay, timing.activationDelay) : timing.activationDelay
    }

    /// `time == nil` re-evaluates without restarting dwell timers (modifier changes).
    private mutating func evaluate(cursor: CGPoint, time: TimeInterval?) -> [SnapEffect] {
        lastCursor = cursor
        if !detector.isNearSharedEdge(cursor) {
            approachDisplay = detector.topology.display(containing: cursor)?.id
        }
        let session: SnapSessionID, window: WindowToken, current: ZoneCandidate?
        switch state {
        case let .trackingDrag(s, w): (session, window, current) = (s, w, nil)
        case let .candidate(s, w, z, _): (session, window, current) = (s, w, z)
        case let .previewing(s, w, z): (session, window, current) = (s, w, z)
        default: return []
        }
        let wasPreviewing = isPreviewing
        let found = suppressed ? nil : detector.detect(cursor: cursor, current: current, approach: approachDisplay)

        guard let found else {
            state = .trackingDrag(session: session, window: window)
            return wasPreviewing ? [.hidePreview] : []
        }
        if found.zone == current?.zone {
            if case let .candidate(_, _, _, since) = state, let time, time - since >= delay(for: found) {
                state = .previewing(session: session, window: window, zone: found)
                return [.showPreview(found.zone)]
            }
            return []
        }
        // New zone.
        if delay(for: found) <= 0 {
            state = .previewing(session: session, window: window, zone: found)
            return [.showPreview(found.zone)]
        }
        state = .candidate(session: session, window: window, zone: found, since: time ?? 0)
        return wasPreviewing ? [.hidePreview] : []
    }
}
