import CoreGraphics

extension CGRect {
    public var area: CGFloat { isNull ? 0 : width * height }

    public var center: CGPoint { CGPoint(x: midX, y: midY) }

    /// Area of the intersection with `other`, zero when disjoint.
    public func intersectionArea(with other: CGRect) -> CGFloat {
        let i = intersection(other)
        return i.isNull ? 0 : i.area
    }

    /// Whether every edge is within `tolerance` points of `other`'s.
    public func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    /// Rounds origin and size to whole points (AX positions are effectively integral).
    public var roundedToPoints: CGRect {
        CGRect(x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded())
    }

    /// Squared distance from `point` to the closest point of the rect (0 when inside).
    public func squaredDistance(to point: CGPoint) -> CGFloat {
        let dx = Swift.max(minX - point.x, 0, point.x - maxX)
        let dy = Swift.max(minY - point.y, 0, point.y - maxY)
        return dx * dx + dy * dy
    }

    /// Like `contains(_:)` but treats the max edges as inside, which matters for the
    /// cursor sitting exactly on the right/bottom edge of the right/bottom-most display.
    public func containsInclusive(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}
