import ApplicationServices
import Darwin
import Foundation
import PaneFlowCore

public enum GeometryOperationError: Error, Sendable, Equatable {
    case processTerminated
    case windowGone
    case ineligible(IneligibilityReason)
    case notMovable
    case notResizable
    case applicationUnresponsive
    case accessibility(AXFailure)
    /// The app did not adopt the frame and the previous frame was restored (or left untouched).
    case verificationFailed(requested: CGRect, actual: CGRect, restored: Bool)
}

public struct GeometryOperationResult: Sendable, Equatable {
    public let token: WindowToken
    public let previousFrame: CGRect
    public let requestedFrame: CGRect
    public let actualFrame: CGRect
    public let verdict: GeometryVerdict
    public let milliseconds: Double
}

/// Applies a frame to a window as a verified operation (see ARCHITECTURE.md §5).
public final class WindowGeometryController: Sendable {
    private let repository: WindowRepository
    private let executor: AccessibilityExecutor
    private let eligibility: WindowEligibilityPolicy

    public init(
        repository: WindowRepository,
        executor: AccessibilityExecutor = .shared,
        eligibility: WindowEligibilityPolicy = WindowEligibilityPolicy(ownProcessID: getpid())
    ) {
        self.repository = repository
        self.executor = executor
        self.eligibility = eligibility
    }

    /// Validates, applies, re-reads and classifies. At most one corrective position write; no retry loops.
    public func apply(_ requested: CGRect, to token: WindowToken) async throws(GeometryOperationError) -> GeometryOperationResult {
        guard let element = repository.element(for: token), let app = repository.application(for: token) else {
            throw .windowGone
        }
        let target = requested.roundedToPoints
        let policy = eligibility
        let outcome: Result<GeometryOperationResult, GeometryOperationError> = await executor.perform {
            let clock = ContinuousClock()
            let start = clock.now

            // 1. Process alive.
            guard Self.processIsAlive(app.pid) else { return .failure(.processTerminated) }

            // 2. Window still valid + 3. eligibility (fresh read, never a cached snapshot).
            let before: CGRect
            do throws(AXFailure) {
                before = try element.frame()
                let snapshot = WindowSnapshot(
                    token: token, pid: app.pid, bundleIdentifier: app.bundleIdentifier, applicationName: app.name,
                    title: nil, role: element.string(kAXRoleAttribute), subrole: element.string(kAXSubroleAttribute),
                    frame: before, isMinimized: element.bool(kAXMinimizedAttribute) ?? false,
                    isMovable: element.isSettable(kAXPositionAttribute),
                    isResizable: element.isSettable(kAXSizeAttribute), isMain: false, isFocused: false
                )
                if case let .ineligible(reason) = policy.evaluate(snapshot) {
                    return .failure(reason == .notMovable ? .notMovable : .ineligible(reason))
                }
                // 4. Settable attributes.
                let sizeChanges = abs(before.width - target.width) > 1 || abs(before.height - target.height) > 1
                if sizeChanges && !snapshot.isResizable { return .failure(.notResizable) }

                // 6. Position → size → position.
                try element.setPosition(target.origin)
                if sizeChanges { try element.setSize(target.size) }
                var after = try element.frame()
                if !after.origin.equalTo(target.origin) {
                    try element.setPosition(target.origin)
                    after = try element.frame()
                }

                // 7–8. Verify.
                let verdict = GeometryVerifier.verify(requested: target, actual: after)
                let elapsed = (clock.now - start).milliseconds
                PerformanceMonitor.shared.record("window.geometry.apply", milliseconds: elapsed)

                guard verdict.isAcceptable else {
                    // 9. Restore only if nobody else moved the window since our write.
                    var restored = false
                    if let current = try? element.frame(), current.isApproximatelyEqual(to: after) {
                        try? element.setPosition(before.origin)
                        try? element.setSize(before.size)
                        restored = (try? element.frame())?.isApproximatelyEqual(to: before) ?? false
                    }
                    return .failure(.verificationFailed(requested: target, actual: after, restored: restored))
                }
                return .success(GeometryOperationResult(
                    token: token, previousFrame: before, requestedFrame: target,
                    actualFrame: after, verdict: verdict, milliseconds: elapsed
                ))
            } catch {
                switch error {
                case .invalidElement: return .failure(.windowGone)
                case .cannotComplete: return .failure(Self.processIsAlive(app.pid) ? .applicationUnresponsive : .processTerminated)
                default: return .failure(.accessibility(error))
                }
            }
        }

        switch outcome {
        case let .success(result):
            Log.geometry.info("Applied frame to \(token, privacy: .public): \(String(describing: result.verdict), privacy: .public) in \(result.milliseconds, format: .fixed(precision: 1)) ms")
            return result
        case let .failure(error):
            if error == .windowGone { repository.forget(token) }
            Log.geometry.error("Failed to apply frame to \(token, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Unverified fast path for continuous updates (linked resizing while the mouse moves).
    /// Writes only the attributes that change; the gesture ends with a verified `apply`.
    public func applyLive(_ frames: [WindowToken: CGRect]) async {
        let work = frames.compactMap { token, frame in repository.element(for: token).map { ($0, frame.roundedToPoints) } }
        guard !work.isEmpty else { return }
        await executor.perform {
            for (element, target) in work {
                guard let current = try? element.frame() else { continue }
                if !current.origin.equalTo(target.origin) { try? element.setPosition(target.origin) }
                if !current.size.equalTo(target.size) { try? element.setSize(target.size) }
            }
        }
    }

    /// `kill(pid, 0)` probes existence without sending a signal; safe from any thread.
    static func processIsAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
