import CoreGraphics
import Foundation
import PaneFlowCore

/// Remembers the frame a window had before PaneFlow first changed it, so it can be restored.
///
/// In-memory only: frames refer to session-scoped tokens and must not survive a relaunch.
public final class WindowRestoreManager: @unchecked Sendable {
    private let lock = NSLock()
    private var originals: [WindowToken: CGRect] = [:]
    private let capacity: Int

    public init(capacity: Int = 256) {
        self.capacity = capacity
    }

    /// Records `frame` only if nothing is recorded yet: consecutive snaps keep the *original* frame.
    public func recordOriginal(_ frame: CGRect, for token: WindowToken) {
        lock.withLock {
            guard originals[token] == nil else { return }
            if originals.count >= capacity, let evict = originals.keys.min(by: { $0.rawValue < $1.rawValue }) {
                originals.removeValue(forKey: evict)
            }
            originals[token] = frame
        }
    }

    public func original(for token: WindowToken) -> CGRect? {
        lock.withLock { originals[token] }
    }

    public func clear(_ token: WindowToken) {
        _ = lock.withLock { originals.removeValue(forKey: token) }
    }
}
