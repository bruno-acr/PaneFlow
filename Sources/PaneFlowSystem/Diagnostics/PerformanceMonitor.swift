import Foundation
import PaneFlowCore

/// Thread-safe registry of latency statistics keyed by metric name (e.g. `window.geometry.apply`).
public final class PerformanceMonitor: @unchecked Sendable {
    public static let shared = PerformanceMonitor()

    private let lock = NSLock()
    private var metrics: [String: LatencyStatistics] = [:]

    public init() {}

    public func record(_ metric: String, milliseconds: Double) {
        lock.withLock {
            metrics[metric, default: LatencyStatistics()].record(milliseconds)
        }
    }

    public struct Summary: Sendable, Codable, Equatable {
        public let metric: String
        public let count: Int
        public let p50: Double?
        public let p95: Double?
    }

    public func summaries() -> [Summary] {
        lock.withLock {
            metrics.map { Summary(metric: $0.key, count: $0.value.totalCount, p50: $0.value.p50, p95: $0.value.p95) }
                .sorted { $0.metric < $1.metric }
        }
    }
}
