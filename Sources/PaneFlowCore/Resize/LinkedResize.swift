import CoreGraphics

/// Adjacent-window resizing: when the user drags the edge shared by side-by-side windows, the
/// windows on the other side of that edge follow, like a Windows 11 Snap Group divider.
///
/// macOS offers no way to put a real divider between windows of other apps, so the gesture is the
/// app's own resize handle. PaneFlow observes which window changes size (the *driver*) and moves the
/// edges of its neighbours to match.
public enum LinkedResize {
    public enum Edge: Sendable, CaseIterable {
        case left, right, top, bottom

        var isHorizontalAxis: Bool { self == .left || self == .right }
    }

    public struct Candidate: Sendable, Equatable {
        public let token: WindowToken
        public let frame: CGRect
        public init(token: WindowToken, frame: CGRect) {
            self.token = token
            self.frame = frame
        }
    }

    public enum Relation: Sendable, Equatable {
        /// The follower's *opposite* edge touches the driver's edge (window on the other side).
        case opposite
        /// The follower's *same* edge is aligned with the driver's edge (stacked in the same column/row).
        case aligned
    }

    public struct Follower: Sendable, Equatable {
        public let token: WindowToken
        public let original: CGRect
        public let relation: Relation
    }

    public struct Plan: Sendable, Equatable {
        public let edge: Edge
        public let followers: [Follower]
        public var isEmpty: Bool { followers.isEmpty }
    }

    public struct Tuning: Sendable, Equatable {
        /// Max distance between touching edges (covers configured gaps and app rounding).
        public var adjacency: CGFloat = 20
        /// Max misalignment for windows sharing the same edge line.
        public var alignment: CGFloat = 4
        /// Fraction of the shorter window that must overlap along the edge.
        public var minimumOverlap: CGFloat = 0.25
        /// Followers are never made smaller than this along the resized axis.
        public var minimumLength: CGFloat = 160

        public init() {}
    }

    // MARK: Planning

    /// Windows that should follow when `edge` of `driver` moves. `candidates` must not include the driver.
    public static func plan(driver: CGRect, edge: Edge, candidates: [Candidate], tuning: Tuning = Tuning()) -> Plan {
        // Work in an axis where the edge is vertical (left/right); transpose top/bottom.
        let flip = !edge.isHorizontalAxis
        let d = flip ? driver.transposed : driver
        let isMaxEdge = edge == .right || edge == .bottom
        let items = candidates.map { (token: $0.token, frame: flip ? $0.frame.transposed : $0.frame, original: $0.frame) }

        func edgeValue(_ r: CGRect, max: Bool) -> CGFloat { max ? r.maxX : r.minX }
        func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
            let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
            return overlap > tuning.minimumOverlap * min(a.height, b.height)
        }
        func stacked(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minY - b.maxY) <= tuning.adjacency || abs(a.maxY - b.minY) <= tuning.adjacency
        }

        let line = edgeValue(d, max: isMaxEdge)

        // Same-side windows whose edge lies on the same line, chained vertically from the driver.
        var column = [d]
        var aligned: [Follower] = []
        var remaining = items
        var grew = true
        while grew {
            grew = false
            for (i, item) in remaining.enumerated().reversed()
            where abs(edgeValue(item.frame, max: isMaxEdge) - line) <= tuning.alignment
                && column.contains(where: { stacked($0, item.frame) }) {
                column.append(item.frame)
                aligned.append(Follower(token: item.token, original: item.original, relation: .aligned))
                remaining.remove(at: i)
                grew = true
            }
        }

        // Windows on the other side of the line, touching any window of the column.
        let opposite = remaining.filter { item in
            let touching = isMaxEdge
                ? item.frame.minX - line >= -tuning.alignment && item.frame.minX - line <= tuning.adjacency
                : line - item.frame.maxX >= -tuning.alignment && line - item.frame.maxX <= tuning.adjacency
            return touching && column.contains { overlaps($0, item.frame) }
        }.map { Follower(token: $0.token, original: $0.original, relation: .opposite) }

        return Plan(edge: edge, followers: aligned + opposite)
    }

    // MARK: Following

    /// Which edges of the driver moved (resize, not move) between `original` and `current`.
    public static func movedEdges(original: CGRect, current: CGRect, threshold: CGFloat = 0.5) -> [Edge] {
        func moved(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) > threshold }
        var edges: [Edge] = []
        let sizeChangedX = moved(original.width, current.width)
        let sizeChangedY = moved(original.height, current.height)
        if sizeChangedX {
            if moved(original.minX, current.minX) { edges.append(.left) }
            if moved(original.maxX, current.maxX) { edges.append(.right) }
        }
        if sizeChangedY {
            if moved(original.minY, current.minY) { edges.append(.top) }
            if moved(original.maxY, current.maxY) { edges.append(.bottom) }
        }
        return edges
    }

    /// New frames for every follower of `plans`, given the driver's original and current frames.
    /// Gaps between windows are preserved; followers are clamped to `tuning.minimumLength`.
    public static func followerFrames(
        plans: [Plan], driverOriginal: CGRect, driverCurrent: CGRect, tuning: Tuning = Tuning()
    ) -> [WindowToken: CGRect] {
        var result: [WindowToken: CGRect] = [:]
        for plan in plans {
            for follower in plan.followers {
                var frame = result[follower.token] ?? follower.original
                switch (plan.edge, follower.relation) {
                case (.right, .opposite):
                    let gap = follower.original.minX - driverOriginal.maxX
                    frame = frame.withMinX(min(driverCurrent.maxX + gap, frame.maxX - tuning.minimumLength))
                case (.left, .opposite):
                    let gap = driverOriginal.minX - follower.original.maxX
                    frame = frame.withMaxX(max(driverCurrent.minX - gap, frame.minX + tuning.minimumLength))
                case (.bottom, .opposite):
                    let gap = follower.original.minY - driverOriginal.maxY
                    frame = frame.withMinY(min(driverCurrent.maxY + gap, frame.maxY - tuning.minimumLength))
                case (.top, .opposite):
                    let gap = driverOriginal.minY - follower.original.maxY
                    frame = frame.withMaxY(max(driverCurrent.minY - gap, frame.minY + tuning.minimumLength))
                case (.right, .aligned):
                    frame = frame.withMaxX(max(driverCurrent.maxX + (follower.original.maxX - driverOriginal.maxX), frame.minX + tuning.minimumLength))
                case (.left, .aligned):
                    frame = frame.withMinX(min(driverCurrent.minX + (follower.original.minX - driverOriginal.minX), frame.maxX - tuning.minimumLength))
                case (.bottom, .aligned):
                    frame = frame.withMaxY(max(driverCurrent.maxY + (follower.original.maxY - driverOriginal.maxY), frame.minY + tuning.minimumLength))
                case (.top, .aligned):
                    frame = frame.withMinY(min(driverCurrent.minY + (follower.original.minY - driverOriginal.minY), frame.maxY - tuning.minimumLength))
                }
                result[follower.token] = frame.roundedToPoints
            }
        }
        return result
    }

    /// When a follower refused to shrink (app minimum size), the driver must stop at the follower's
    /// actual edge instead of overlapping it. Returns the corrected driver frame, or nil if none is needed.
    public static func driverCorrection(
        plans: [Plan], driverCurrent: CGRect, followerActual: [WindowToken: CGRect], tolerance: CGFloat = 2
    ) -> CGRect? {
        var corrected = driverCurrent
        for plan in plans {
            for follower in plan.followers where follower.relation == .opposite {
                guard let actual = followerActual[follower.token] else { continue }
                switch plan.edge {
                case .right:
                    if actual.minX < corrected.maxX - tolerance { corrected = corrected.withMaxX(actual.minX) }
                case .left:
                    if actual.maxX > corrected.minX + tolerance { corrected = corrected.withMinX(actual.maxX) }
                case .bottom:
                    if actual.minY < corrected.maxY - tolerance { corrected = corrected.withMaxY(actual.minY) }
                case .top:
                    if actual.maxY > corrected.minY + tolerance { corrected = corrected.withMinY(actual.maxY) }
                }
            }
        }
        return corrected == driverCurrent ? nil : corrected
    }
}

extension CGRect {
    var transposed: CGRect { CGRect(x: minY, y: minX, width: height, height: width) }

    func withMinX(_ v: CGFloat) -> CGRect { CGRect(x: v, y: minY, width: maxX - v, height: height) }
    func withMaxX(_ v: CGFloat) -> CGRect { CGRect(x: minX, y: minY, width: v - minX, height: height) }
    func withMinY(_ v: CGFloat) -> CGRect { CGRect(x: minX, y: v, width: width, height: maxY - v) }
    func withMaxY(_ v: CGFloat) -> CGRect { CGRect(x: minX, y: minY, width: width, height: v - minY) }
}
