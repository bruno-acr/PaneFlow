import CoreGraphics

/// Spacing applied when turning unit slots into concrete frames.
public struct LayoutSpacing: Sendable, Equatable, Codable {
    /// Distance between adjacent windows.
    public var gap: CGFloat
    /// Inset from the edges of the usable area.
    public var margin: CGFloat

    public init(gap: CGFloat = 0, margin: CGFloat = 0) {
        self.gap = max(0, gap)
        self.margin = max(0, margin)
    }

    public static let none = LayoutSpacing()
}

/// Turns layout definitions into concrete global frames.
public enum LayoutEngine {
    /// Frames for every slot of `layout` inside `area` (global coordinates, usually a display's visible frame).
    ///
    /// Slot boundaries are snapped to whole points *before* gaps are applied, so adjacent slots
    /// share exact edges and never overlap or leave sub-point slivers. Internal edges receive half
    /// of the gap on each side; outer edges receive the margin.
    public static func frames(for layout: LayoutDefinition, in area: CGRect, spacing: LayoutSpacing = .none) -> [CGRect] {
        let content = area.insetBy(dx: spacing.margin, dy: spacing.margin)
        guard content.width > 0, content.height > 0 else { return layout.slots.map { _ in .zero } }
        let halfGap = spacing.gap / 2
        let epsilon: CGFloat = 1e-9

        return layout.slots.map { slot in
            let u = slot.unitRect
            func boundaryX(_ f: CGFloat) -> CGFloat { (content.minX + f * content.width).rounded() }
            func boundaryY(_ f: CGFloat) -> CGFloat { (content.minY + f * content.height).rounded() }

            var minX = boundaryX(u.minX), maxX = boundaryX(u.maxX)
            var minY = boundaryY(u.minY), maxY = boundaryY(u.maxY)
            if u.minX > epsilon { minX += halfGap }
            if u.maxX < 1 - epsilon { maxX -= halfGap }
            if u.minY > epsilon { minY += halfGap }
            if u.maxY < 1 - epsilon { maxY -= halfGap }
            return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
        }
    }

    /// Frame of a window of `size` centred in `area`, clamped so it never exceeds the area.
    public static func centered(size: CGSize, in area: CGRect) -> CGRect {
        let w = min(size.width, area.width), h = min(size.height, area.height)
        return CGRect(x: (area.midX - w / 2).rounded(), y: (area.midY - h / 2).rounded(), width: w, height: h)
    }
}
