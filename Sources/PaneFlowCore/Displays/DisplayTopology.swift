import CoreGraphics

/// Immutable description of one display, expressed in global (CG/AX) points.
public struct DisplayDescriptor: Sendable, Equatable, Identifiable {
    /// `CGDirectDisplayID`. Valid only while the display stays connected.
    public let id: UInt32
    /// Stable identity across reconnections (`CGDisplayCreateUUIDFromDisplayID`), when available.
    public let persistentID: String?
    public let name: String
    /// Full display bounds.
    public let frame: CGRect
    /// Bounds minus menu bar and Dock: the area layouts are allowed to use.
    public let visibleFrame: CGRect
    public let scale: CGFloat
    public let isPrimary: Bool

    public init(
        id: UInt32, persistentID: String?, name: String,
        frame: CGRect, visibleFrame: CGRect, scale: CGFloat, isPrimary: Bool
    ) {
        self.id = id
        self.persistentID = persistentID
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
        self.isPrimary = isPrimary
    }
}

/// A snapshot of the connected displays. Rebuilt (never mutated) when the configuration changes.
public struct DisplayTopology: Sendable, Equatable {
    public let displays: [DisplayDescriptor]

    public init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    public var primary: DisplayDescriptor? {
        displays.first(where: \.isPrimary) ?? displays.first
    }

    public func display(withID id: UInt32) -> DisplayDescriptor? {
        displays.first { $0.id == id }
    }

    /// Display under a global point; falls back to the nearest display so that a cursor in a
    /// gap between misaligned displays still resolves deterministically.
    public func display(containing point: CGPoint) -> DisplayDescriptor? {
        if let hit = displays.first(where: { $0.frame.containsInclusive(point) }) {
            return hit
        }
        return displays.min { $0.frame.squaredDistance(to: point) < $1.frame.squaredDistance(to: point) }
    }

    /// Display that holds the largest part of `rect` (how macOS itself assigns a window to a display).
    /// Falls back to the display nearest to the rect's centre when the rect is entirely off-screen.
    public func display(for rect: CGRect) -> DisplayDescriptor? {
        let best = displays.max { $0.frame.intersectionArea(with: rect) < $1.frame.intersectionArea(with: rect) }
        if let best, best.frame.intersectionArea(with: rect) > 0 {
            return best
        }
        return display(containing: rect.center)
    }

    public enum Direction: Sendable { case left, right, up, down }

    /// The display next to `id` in `direction`: prefers displays that touch the edge and overlap
    /// along it, then the nearest display whose centre lies in that direction.
    public func display(adjacentTo id: UInt32, direction: Direction) -> DisplayDescriptor? {
        guard let from = display(withID: id)?.frame else { return nil }
        let others = displays.filter { $0.id != id }
        func inDirection(_ o: CGRect) -> Bool {
            switch direction {
            case .left: o.midX < from.midX && o.maxX <= from.minX + 1
            case .right: o.midX > from.midX && o.minX >= from.maxX - 1
            case .up: o.midY < from.midY && o.maxY <= from.minY + 1
            case .down: o.midY > from.midY && o.minY >= from.maxY - 1
            }
        }
        func overlap(_ o: CGRect) -> CGFloat {
            switch direction {
            case .left, .right: max(0, min(o.maxY, from.maxY) - max(o.minY, from.minY))
            case .up, .down: max(0, min(o.maxX, from.maxX) - max(o.minX, from.minX))
            }
        }
        func gap(_ o: CGRect) -> CGFloat {
            switch direction {
            case .left: from.minX - o.maxX
            case .right: o.minX - from.maxX
            case .up: from.minY - o.maxY
            case .down: o.minY - from.maxY
            }
        }
        return others.filter { inDirection($0.frame) }.min { a, b in
            let oa = overlap(a.frame) > 0, ob = overlap(b.frame) > 0
            if oa != ob { return oa }
            return gap(a.frame) < gap(b.frame)
        }
    }

    /// Next display in left-to-right, then top-to-bottom order (wrapping), used by "move to next display".
    public func display(after id: UInt32) -> DisplayDescriptor? {
        let ordered = displays.sorted {
            ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY)
        }
        guard let index = ordered.firstIndex(where: { $0.id == id }), ordered.count > 1 else { return nil }
        return ordered[(index + 1) % ordered.count]
    }
}
