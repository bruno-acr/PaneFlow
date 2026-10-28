import CoreGraphics

/// Decides which empty regions Snap Assist offers to fill after a snap.
public enum SnapAssistPlanner {
    /// Regions left empty by snapping into `region`, in the order they are offered.
    public static func complement(of region: SnapRegion) -> [SnapRegion] {
        switch region {
        case .leftHalf: [.rightHalf]
        case .rightHalf: [.leftHalf]
        case .topHalf: [.bottomHalf]
        case .bottomHalf: [.topHalf]
        case .maximize: []
        case .topLeftQuarter: [.topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]
        case .topRightQuarter: [.topLeftQuarter, .bottomLeftQuarter, .bottomRightQuarter]
        case .bottomLeftQuarter: [.topLeftQuarter, .topRightQuarter, .bottomRightQuarter]
        case .bottomRightQuarter: [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter]
        }
    }

    /// Complement regions on `area` that no window in `occupied` already fills (within `tolerance`).
    public static func emptyRegions(
        after region: SnapRegion, in area: CGRect, occupied: [CGRect], spacing: LayoutSpacing = .none, tolerance: CGFloat = 24
    ) -> [SnapRegion] {
        complement(of: region).filter { candidate in
            let frame = candidate.frame(in: area, spacing: spacing)
            return !occupied.contains { $0.isApproximatelyEqual(to: frame, tolerance: tolerance) }
        }
    }
}

extension SnapAssistPlanner {
    /// The frame that fills **exactly** the empty space of `region`, given the actual frames of the
    /// windows already placed in this layout (`placed`). Each edge of the nominal region that faces a
    /// placed window moves to that window's edge (minus `gap`), so the new window neither leaves a
    /// hole nor overlaps when the first window is not at its nominal size (app minimums, a 40/60
    /// split…). Edges with no placed window in front keep their nominal position.
    public static func fillFrame(
        for region: SnapRegion, in area: CGRect, placed: [CGRect], spacing: LayoutSpacing = .none
    ) -> CGRect {
        let nominal = region.frame(in: area, spacing: spacing)
        let content = area.insetBy(dx: spacing.margin, dy: spacing.margin)
        func overlapsVertically(_ w: CGRect) -> Bool {
            min(w.maxY, nominal.maxY) - max(w.minY, nominal.minY) > 0.25 * min(w.height, nominal.height)
        }
        func overlapsHorizontally(_ w: CGRect) -> Bool {
            min(w.maxX, nominal.maxX) - max(w.minX, nominal.minX) > 0.25 * min(w.width, nominal.width)
        }
        var minX = nominal.minX, maxX = nominal.maxX, minY = nominal.minY, maxY = nominal.maxY
        let gap = spacing.gap
        // Right edge: nearest placed window to the right of the region's centre.
        let right = placed.filter { $0.minX > nominal.midX && $0.minX <= content.maxX && overlapsVertically($0) }.map(\.minX).min()
        if let right { maxX = right - gap }
        let left = placed.filter { $0.maxX < nominal.midX && $0.maxX >= content.minX && overlapsVertically($0) }.map(\.maxX).max()
        if let left { minX = left + gap }
        let below = placed.filter { $0.minY > nominal.midY && $0.minY <= content.maxY && overlapsHorizontally($0) }.map(\.minY).min()
        if let below { maxY = below - gap }
        let above = placed.filter { $0.maxY < nominal.midY && $0.maxY >= content.minY && overlapsHorizontally($0) }.map(\.maxY).max()
        if let above { minY = above + gap }
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY)).roundedToPoints
    }

    /// When the chosen window ends up larger than `target` (its app imposes a minimum size), keep it
    /// inside the usable area — anchored to the screen edge the target touches — and shrink the placed
    /// neighbours it would cover so that nothing overlaps. Returns nil when no correction is needed.
    public static func resolveOverflow(
        target: CGRect, actual: CGRect, area: CGRect, neighbours: [WindowToken: CGRect], tolerance: CGFloat = 2
    ) -> (chosen: CGRect, neighbours: [WindowToken: CGRect])? {
        var chosen = actual
        var changed = false
        if actual.width > target.width + tolerance {
            chosen.origin.x = abs(target.maxX - area.maxX) <= tolerance ? area.maxX - actual.width
                : abs(target.minX - area.minX) <= tolerance ? area.minX : target.minX
            changed = true
        }
        if actual.height > target.height + tolerance {
            chosen.origin.y = abs(target.maxY - area.maxY) <= tolerance ? area.maxY - actual.height
                : abs(target.minY - area.minY) <= tolerance ? area.minY : target.minY
            changed = true
        }
        guard changed else { return nil }
        var adjusted: [WindowToken: CGRect] = [:]
        for (token, frame) in neighbours where frame.intersectionArea(with: chosen) > 1 {
            var f = frame
            let i = f.intersection(chosen)
            if i.width <= i.height {
                // Side by side: trim the horizontal overlap.
                if f.midX < chosen.midX { f.size.width = chosen.minX - f.minX }
                else { let maxX = f.maxX; f.origin.x = chosen.maxX; f.size.width = maxX - chosen.maxX }
            } else {
                if f.midY < chosen.midY { f.size.height = chosen.minY - f.minY }
                else { let maxY = f.maxY; f.origin.y = chosen.maxY; f.size.height = maxY - chosen.maxY }
            }
            adjusted[token] = f.roundedToPoints
        }
        return (chosen.roundedToPoints, adjusted)
    }
}

/// Window arrangements that operate on a group of tiled windows.
public enum TileArrangement {
    public enum Axis: Sendable, Equatable { case horizontal, vertical }

    /// Windows connected to `start` through shared edges (side by side or stacked), including `start`.
    public static func connectedGroup(
        from start: WindowToken, windows: [LinkedResize.Candidate], tolerance: CGFloat = 20
    ) -> [LinkedResize.Candidate] {
        guard let first = windows.first(where: { $0.token == start }) else { return [] }
        var group = [first]
        var queue = [first]
        var remaining = windows.filter { $0.token != start }
        while let current = queue.popLast() {
            let neighbours = remaining.filter { adjacency(current.frame, $0.frame, tolerance: tolerance) != nil }
            remaining.removeAll { n in neighbours.contains { $0.token == n.token } }
            group += neighbours
            queue += neighbours
        }
        return group
    }

    /// Axis along which `a` and `b` touch, or nil.
    public static func adjacency(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 20) -> Axis? {
        func overlap(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> Bool {
            min(a1, b1) - max(a0, b0) > 0.25 * min(a1 - a0, b1 - b0)
        }
        if (abs(a.maxX - b.minX) <= tolerance || abs(b.maxX - a.minX) <= tolerance), overlap(a.minY, a.maxY, b.minY, b.maxY) {
            return .horizontal
        }
        if (abs(a.maxY - b.minY) <= tolerance || abs(b.maxY - a.minY) <= tolerance), overlap(a.minX, a.maxX, b.minX, b.maxX) {
            return .vertical
        }
        return nil
    }

    /// Horizontal when any two windows of the group sit side by side; vertical when they are only stacked.
    public static func swapAxis(for group: [LinkedResize.Candidate]) -> Axis {
        for (i, a) in group.enumerated() {
            for b in group[(i + 1)...] where adjacency(a.frame, b.frame) == .horizontal {
                return .horizontal
            }
        }
        return group.count > 1 ? .vertical : .horizontal
    }

    /// Mirrors every window of `group` inside `area`: left ↔ right (or top ↔ bottom). Sizes and gaps
    /// are preserved, so a 30/70 split becomes 70/30 with the windows exchanged.
    public static func mirrored(_ group: [LinkedResize.Candidate], in area: CGRect, axis: Axis) -> [WindowToken: CGRect] {
        var result: [WindowToken: CGRect] = [:]
        for window in group {
            var f = window.frame
            switch axis {
            case .horizontal: f.origin.x = area.minX + area.maxX - window.frame.maxX
            case .vertical: f.origin.y = area.minY + area.maxY - window.frame.maxY
            }
            result[window.token] = f.roundedToPoints
        }
        return result
    }
}
