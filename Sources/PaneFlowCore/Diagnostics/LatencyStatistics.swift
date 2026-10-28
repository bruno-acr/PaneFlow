import Foundation

/// Bounded reservoir of latency samples with percentile reporting.
///
/// Keeps only the most recent `capacity` samples so memory stays constant in a resident app.
public struct LatencyStatistics: Sendable, Equatable {
    public let capacity: Int
    public private(set) var samples: [Double] = []
    public private(set) var totalCount = 0
    private var nextIndex = 0

    public init(capacity: Int = 512) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    /// - Parameter milliseconds: duration of one operation.
    public mutating func record(_ milliseconds: Double) {
        totalCount += 1
        if samples.count < capacity {
            samples.append(milliseconds)
        } else {
            samples[nextIndex] = milliseconds
        }
        nextIndex = (nextIndex + 1) % capacity
    }

    /// Nearest-rank percentile (`p` in 0…100); nil when empty.
    public func percentile(_ p: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    public var p50: Double? { percentile(50) }
    public var p95: Double? { percentile(95) }
}
