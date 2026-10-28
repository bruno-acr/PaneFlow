import CoreGraphics

/// Outcome of comparing the frame we requested with the frame the application actually adopted.
public enum GeometryVerdict: Sendable, Equatable {
    /// Every edge within tolerance.
    case exact
    /// The app moved to the requested origin region but imposed its own size
    /// (minimum/maximum size, resize increments such as Terminal's character grid).
    case adjustedByApplication(requested: CGRect, actual: CGRect)
    /// The window did not end up where we asked.
    case failed(requested: CGRect, actual: CGRect)

    public var isAcceptable: Bool {
        switch self {
        case .exact, .adjustedByApplication: true
        case .failed: false
        }
    }
}

public enum GeometryVerifier {
    /// - Parameters:
    ///   - tolerance: per-edge tolerance for an exact match.
    ///   - adjustmentTolerance: how far the origin may drift and still count as an app-imposed
    ///     adjustment rather than a failure. Size differences are always accepted as adjustments
    ///     as long as the window overlaps most of the requested area.
    public static func verify(
        requested: CGRect,
        actual: CGRect,
        tolerance: CGFloat = 1,
        adjustmentTolerance: CGFloat = 40
    ) -> GeometryVerdict {
        if actual.isApproximatelyEqual(to: requested, tolerance: tolerance) {
            return .exact
        }
        let originClose = abs(actual.minX - requested.minX) <= adjustmentTolerance
            && abs(actual.minY - requested.minY) <= adjustmentTolerance
        let overlap = requested.area > 0 ? actual.intersectionArea(with: requested) / requested.area : 0
        if originClose && overlap >= 0.5 {
            return .adjustedByApplication(requested: requested, actual: actual)
        }
        return .failed(requested: requested, actual: actual)
    }
}
