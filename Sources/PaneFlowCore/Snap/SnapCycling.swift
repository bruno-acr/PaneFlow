import CoreGraphics

/// Keyboard snapping that walks across displays, like Windows' Win+←/→:
/// ← on a window already on the left half moves it to the right half of the display on the left;
/// on the right half it goes to the left half of the same display; otherwise it snaps to the left half.
public enum SnapCycling {
    public enum Direction: Sendable { case left, right }

    public static func target(
        direction: Direction, windowFrame: CGRect, topology: DisplayTopology,
        spacing: LayoutSpacing = .none, tolerance: CGFloat = 24
    ) -> SnapZone? {
        guard let display = topology.display(for: windowFrame) else { return nil }
        func occupies(_ region: SnapRegion) -> Bool {
            let r = region.frame(in: display.visibleFrame, spacing: spacing)
            // Tolerant: apps may round the size (e.g. Terminal's character grid).
            return abs(r.minX - windowFrame.minX) <= tolerance && abs(r.minY - windowFrame.minY) <= tolerance
                && abs(r.width - windowFrame.width) <= tolerance
        }
        let (toward, away): (SnapRegion, SnapRegion) = direction == .left ? (.leftHalf, .rightHalf) : (.rightHalf, .leftHalf)

        if occupies(toward) {
            let next = topology.display(adjacentTo: display.id, direction: direction == .left ? .left : .right)
            return next.map { SnapZone(region: away, displayID: $0.id) }
        }
        if occupies(away) {
            return SnapZone(region: toward, displayID: display.id)
        }
        return SnapZone(region: toward, displayID: display.id)
    }
}
