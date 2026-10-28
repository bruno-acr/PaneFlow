import ApplicationServices
import Foundation

/// Runs blocking Accessibility IPC off the main thread on one serial queue.
///
/// Serial on purpose: AX calls that move/resize the same window must not interleave. A hung target
/// app delays the queue at most by the messaging timeout per call, never indefinitely.
public final class AccessibilityExecutor: Sendable {
    public static let shared = AccessibilityExecutor()

    /// Upper bound for a single AX round trip (system default is ~6 s).
    public static let messagingTimeout: Float = 0.75

    private let queue = DispatchQueue(label: "app.paneflow.accessibility", qos: .userInitiated)

    private init() {
        // Applies to every element that does not override it.
        AXElement.systemWide.setMessagingTimeout(Self.messagingTimeout)
    }

    public func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try body() })
            }
        }
    }

    public func perform<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: body()) }
        }
    }
}
