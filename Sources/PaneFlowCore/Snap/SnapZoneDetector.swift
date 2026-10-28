import CoreGraphics

public struct SnapZoneSettings: Sendable, Equatable, Codable {
    /// Distance from an outer display edge (one the cursor cannot cross) that activates a zone.
    public var edgeThreshold: CGFloat = 6
    /// Width of the band inside a display along an edge shared with another display. The cursor
    /// crosses such edges freely, so the band must be wide enough to stop in comfortably.
    public var sharedEdgeThreshold: CGFloat = 40
    /// How far the cursor may overshoot *into the neighbouring display* and still mean the edge of
    /// the display the window came from (the approach display).
    public var sharedEdgeOvershoot: CGFloat = 80
    /// Distance along an edge, from a corner, that selects a quarter instead of a half.
    public var cornerSize: CGFloat = 80
    /// Extra distance the cursor must travel out of an active zone before it is dropped (anti-flicker).
    public var hysteresis: CGFloat = 24
    public var topEdgeMaximizes = true
    public var cornersSnapToQuarters = true

    public init() {}
}

public struct ZoneCandidate: Sendable, Equatable {
    public let zone: SnapZone
    /// True when the zone was reached at an edge shared with another display. Such zones require
    /// the cursor to dwell, so that simply moving a window to the other display never snaps it.
    public let onSharedEdge: Bool

    public init(zone: SnapZone, onSharedEdge: Bool) {
        self.zone = zone
        self.onSharedEdge = onSharedEdge
    }
}

/// Maps a cursor position (global coordinates) to a snap zone.
public struct SnapZoneDetector: Sendable {
    public var topology: DisplayTopology
    public var settings: SnapZoneSettings

    public init(topology: DisplayTopology, settings: SnapZoneSettings = SnapZoneSettings()) {
        self.topology = topology
        self.settings = settings
    }

    /// - Parameter approach: the display the drag was last well inside of. Near a shared edge, the
    ///   zone belongs to this display even if the cursor overshot onto the neighbour: dragging a window
    ///   from the MacBook to its left edge means "MacBook left half", not "right half of the monitor
    ///   on the left".
    public func detect(cursor: CGPoint, current: ZoneCandidate? = nil, approach: UInt32? = nil) -> ZoneCandidate? {
        guard let under = topology.display(containing: cursor) else { return nil }
        var display = under
        var point = cursor
        if let approach, approach != under.id, let origin = topology.display(withID: approach),
           let clamped = overshootPoint(cursor, from: origin, into: under) {
            display = origin
            point = clamped
        }
        if let current, current.zone.displayID == display.id,
           let sticky = detect(cursor: point, on: display, slack: settings.hysteresis), sticky.zone == current.zone {
            return sticky
        }
        return detect(cursor: point, on: display, slack: 0)
    }

    /// Whether `cursor` is in any shared-edge band (inside or overshoot side). The approach display is
    /// only updated outside these bands.
    public func isNearSharedEdge(_ cursor: CGPoint) -> Bool {
        guard let display = topology.display(containing: cursor) else { return false }
        let f = display.frame
        let reach = max(settings.sharedEdgeThreshold, settings.sharedEdgeOvershoot) + settings.hysteresis
        return (isShared(.left, of: display, at: cursor) && cursor.x - f.minX <= reach)
            || (isShared(.right, of: display, at: cursor) && f.maxX - cursor.x <= reach)
            || (isShared(.top, of: display, at: cursor) && cursor.y - f.minY <= reach)
            || (isShared(.bottom, of: display, at: cursor) && f.maxY - cursor.y <= reach)
    }

    /// If `cursor` (on `neighbour`) is within the overshoot distance of an edge of `origin` shared
    /// with `neighbour`, returns the cursor pulled back onto that edge of `origin`.
    private func overshootPoint(_ cursor: CGPoint, from origin: DisplayDescriptor, into neighbour: DisplayDescriptor) -> CGPoint? {
        let o = origin.frame
        let clamped = CGPoint(x: min(max(cursor.x, o.minX), o.maxX - 1), y: min(max(cursor.y, o.minY), o.maxY - 1))
        // Only straight across the edge: a cursor past a corner of `origin` is not an overshoot.
        let dx = abs(cursor.x - clamped.x), dy = abs(cursor.y - clamped.y)
        guard (dx == 0 || dy == 0) || (dx <= 1 && dy <= 1) else { return nil }
        guard max(dx, dy) <= settings.sharedEdgeOvershoot + settings.hysteresis else { return nil }
        let edge: Edge
        if cursor.x < o.minX { edge = .left } else if cursor.x >= o.maxX { edge = .right }
        else if cursor.y < o.minY { edge = .top } else { edge = .bottom }
        return isShared(edge, of: origin, at: clamped) ? clamped : nil
    }

    private enum Edge { case left, right, top, bottom }

    private func detect(cursor p: CGPoint, on display: DisplayDescriptor, slack: CGFloat) -> ZoneCandidate? {
        let f = display.frame
        func near(_ edge: Edge) -> (hit: Bool, shared: Bool) {
            let shared = isShared(edge, of: display, at: p)
            let limit = (shared ? settings.sharedEdgeThreshold : settings.edgeThreshold) + slack
            let distance: CGFloat = switch edge {
            case .left: p.x - f.minX
            case .right: f.maxX - p.x
            case .top: p.y - f.minY
            case .bottom: f.maxY - p.y
            }
            return (distance <= limit, shared)
        }

        let left = near(.left), right = near(.right), top = near(.top), bottom = near(.bottom)
        let corner = settings.cornerSize + slack
        let nearTopCorner = p.y - f.minY <= corner
        let nearBottomCorner = f.maxY - p.y <= corner
        let nearLeftCorner = p.x - f.minX <= corner
        let nearRightCorner = f.maxX - p.x <= corner

        func zone(_ region: SnapRegion, shared: Bool) -> ZoneCandidate {
            ZoneCandidate(zone: SnapZone(region: region, displayID: display.id), onSharedEdge: shared)
        }

        if left.hit {
            if settings.cornersSnapToQuarters && nearTopCorner { return zone(.topLeftQuarter, shared: left.shared) }
            if settings.cornersSnapToQuarters && nearBottomCorner { return zone(.bottomLeftQuarter, shared: left.shared) }
            return zone(.leftHalf, shared: left.shared)
        }
        if right.hit {
            if settings.cornersSnapToQuarters && nearTopCorner { return zone(.topRightQuarter, shared: right.shared) }
            if settings.cornersSnapToQuarters && nearBottomCorner { return zone(.bottomRightQuarter, shared: right.shared) }
            return zone(.rightHalf, shared: right.shared)
        }
        if top.hit {
            if settings.cornersSnapToQuarters && nearLeftCorner { return zone(.topLeftQuarter, shared: top.shared) }
            if settings.cornersSnapToQuarters && nearRightCorner { return zone(.topRightQuarter, shared: top.shared) }
            return settings.topEdgeMaximizes ? zone(.maximize, shared: top.shared) : nil
        }
        if bottom.hit, settings.cornersSnapToQuarters {
            if nearLeftCorner { return zone(.bottomLeftQuarter, shared: bottom.shared) }
            if nearRightCorner { return zone(.bottomRightQuarter, shared: bottom.shared) }
        }
        return nil
    }

    /// Whether another display continues across `edge` at the cursor's position along that edge.
    private func isShared(_ edge: Edge, of display: DisplayDescriptor, at p: CGPoint) -> Bool {
        let f = display.frame
        return topology.displays.contains { other in
            guard other.id != display.id else { return false }
            let o = other.frame
            switch edge {
            case .left: return abs(o.maxX - f.minX) <= 1 && p.y >= o.minY && p.y <= o.maxY
            case .right: return abs(o.minX - f.maxX) <= 1 && p.y >= o.minY && p.y <= o.maxY
            case .top: return abs(o.maxY - f.minY) <= 1 && p.x >= o.minX && p.x <= o.maxX
            case .bottom: return abs(o.minY - f.maxY) <= 1 && p.x >= o.minX && p.x <= o.maxX
            }
        }
    }
}
