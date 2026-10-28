import CoreGraphics

/// Makes an edge shared between two displays behave like a real screen edge while a window is
/// being dragged, so it can be snapped to (Windows calls this "ease cursor movement between displays").
///
/// When the cursor crosses a shared edge of the display the drag is coming from, it is held just
/// inside that edge. Every sample the cursor spends past the edge adds its overshoot to a budget;
/// once the user has pushed `distance` points in total, the edge lets go and the window moves to the
/// other display. A fast, deliberate move spends the budget in one or two samples, so moving windows
/// between displays stays effortless. Pure value type: the caller moves the cursor.
public struct EdgeResistance: Sendable, Equatable {
    /// Total push (points) needed to break through a shared edge.
    public var distance: CGFloat = 140
    /// How far back inside the display the cursor must go to re-arm the edge after breaking through.
    public var rearmDistance: CGFloat = 60

    public private(set) var origin: UInt32?
    public private(set) var consumed: CGFloat = 0
    public private(set) var released = false

    public init(distance: CGFloat = 140, rearmDistance: CGFloat = 60) {
        self.distance = distance
        self.rearmDistance = rearmDistance
    }

    public mutating func begin(at point: CGPoint, topology: DisplayTopology) {
        origin = topology.display(containing: point)?.id
        consumed = 0
        released = false
    }

    /// - Returns: the point the cursor should be moved back to, or nil to leave it where it is.
    public mutating func filter(_ point: CGPoint, topology: DisplayTopology) -> CGPoint? {
        guard let originID = origin, let display = topology.display(withID: originID) else {
            origin = topology.display(containing: point)?.id
            return nil
        }
        let f = display.frame
        if f.contains(point) {
            // Back inside: re-arm once clearly away from every edge.
            let inset = f.insetBy(dx: rearmDistance, dy: rearmDistance)
            if inset.contains(point) {
                consumed = 0
                released = false
            }
            return nil
        }
        guard !released else {
            // Broke through: the display now under the cursor becomes the origin once well inside it.
            if let now = topology.display(containing: point), now.id != originID,
               now.frame.insetBy(dx: rearmDistance, dy: rearmDistance).contains(point) {
                origin = now.id
                consumed = 0
                released = false
            }
            return nil
        }
        // Only straight across an edge that another display continues (never at corners or outer edges,
        // where the cursor cannot leave anyway).
        let clamped = CGPoint(x: min(max(point.x, f.minX), f.maxX - 1), y: min(max(point.y, f.minY), f.maxY - 1))
        let dx = abs(point.x - clamped.x), dy = abs(point.y - clamped.y)
        guard dx == 0 || dy == 0 || (dx <= 1 && dy <= 1) else { return nil }
        guard topology.displays.contains(where: { $0.id != originID && $0.frame.containsInclusive(point) }) else { return nil }

        consumed += max(dx, dy)
        if consumed >= distance {
            released = true
            return nil
        }
        return clamped
    }
}
