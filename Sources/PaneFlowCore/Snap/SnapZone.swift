import CoreGraphics

/// Named placements a window can be snapped to on one display.
public enum SnapRegion: String, Sendable, CaseIterable, Codable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter

    /// Layout and slot index that realise this region.
    public var slot: (layout: LayoutDefinition, index: Int) {
        switch self {
        case .leftHalf: (LayoutCatalog.halves, 0)
        case .rightHalf: (LayoutCatalog.halves, 1)
        case .topHalf: (LayoutCatalog.topBottom, 0)
        case .bottomHalf: (LayoutCatalog.topBottom, 1)
        case .maximize: (LayoutCatalog.maximize, 0)
        case .topLeftQuarter: (LayoutCatalog.grid2x2, 0)
        case .topRightQuarter: (LayoutCatalog.grid2x2, 1)
        case .bottomLeftQuarter: (LayoutCatalog.grid2x2, 2)
        case .bottomRightQuarter: (LayoutCatalog.grid2x2, 3)
        }
    }

    public func frame(in area: CGRect, spacing: LayoutSpacing = .none) -> CGRect {
        let (layout, index) = slot
        return LayoutEngine.frames(for: layout, in: area, spacing: spacing)[index]
    }
}

/// A region on a specific display.
public struct SnapZone: Sendable, Equatable, Hashable {
    public let region: SnapRegion
    public let displayID: UInt32

    public init(region: SnapRegion, displayID: UInt32) {
        self.region = region
        self.displayID = displayID
    }

    public func frame(in topology: DisplayTopology, spacing: LayoutSpacing = .none) -> CGRect? {
        topology.display(withID: displayID).map { region.frame(in: $0.visibleFrame, spacing: spacing) }
    }
}
