import CoreGraphics

/// Built-in layouts. Custom layouts (Phase 6) use the same `LayoutDefinition` type.
public enum LayoutCatalog {
    // MARK: One window

    /// Fills the usable area without entering native full screen.
    public static let maximize = LayoutDefinition(id: "maximize", name: "Maximize", slots: [
        LayoutSlot(x: 0, y: 0, width: 1, height: 1),
    ])

    // MARK: Two windows

    public static func verticalSplit(leading fraction: CGFloat) -> LayoutDefinition {
        let percent = Int((fraction * 100).rounded())
        return LayoutDefinition(id: "split-\(percent)-\(100 - percent)", name: "\(percent) / \(100 - percent)", slots: [
            LayoutSlot(x: 0, y: 0, width: fraction, height: 1),
            LayoutSlot(x: fraction, y: 0, width: 1 - fraction, height: 1),
        ])
    }

    public static let halves = verticalSplit(leading: 0.5)
    public static let split40_60 = verticalSplit(leading: 0.4)
    public static let split60_40 = verticalSplit(leading: 0.6)
    public static let split30_70 = verticalSplit(leading: 0.3)
    public static let split70_30 = verticalSplit(leading: 0.7)

    public static let topBottom = LayoutDefinition(id: "top-bottom", name: "Top / Bottom", slots: [
        LayoutSlot(x: 0, y: 0, width: 1, height: 0.5),
        LayoutSlot(x: 0, y: 0.5, width: 1, height: 0.5),
    ])

    // MARK: Three windows

    public static let thirds = LayoutDefinition(id: "thirds", name: "Three Columns", slots: [
        LayoutSlot(x: 0, y: 0, width: 1.0 / 3, height: 1),
        LayoutSlot(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1),
        LayoutSlot(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1),
    ])

    public static let halfAndQuarters = LayoutDefinition(id: "half-quarters", name: "Half + Two Quarters", slots: [
        LayoutSlot(x: 0, y: 0, width: 0.5, height: 1),
        LayoutSlot(x: 0.5, y: 0, width: 0.5, height: 0.5),
        LayoutSlot(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
    ])

    public static let wideCenter = LayoutDefinition(id: "wide-center", name: "Wide Center", slots: [
        LayoutSlot(x: 0, y: 0, width: 0.25, height: 1),
        LayoutSlot(x: 0.25, y: 0, width: 0.5, height: 1),
        LayoutSlot(x: 0.75, y: 0, width: 0.25, height: 1),
    ])

    public static let twoThirdsOneThird = LayoutDefinition(id: "two-thirds-one-third", name: "⅔ + ⅓", slots: [
        LayoutSlot(x: 0, y: 0, width: 2.0 / 3, height: 1),
        LayoutSlot(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1),
    ])

    // MARK: Four windows

    public static let grid2x2 = LayoutDefinition(id: "grid-2x2", name: "Grid 2 × 2", slots: [
        LayoutSlot(x: 0, y: 0, width: 0.5, height: 0.5),
        LayoutSlot(x: 0.5, y: 0, width: 0.5, height: 0.5),
        LayoutSlot(x: 0, y: 0.5, width: 0.5, height: 0.5),
        LayoutSlot(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
    ])

    public static let fourColumns = LayoutDefinition(id: "four-columns", name: "Four Columns", slots: (0..<4).map {
        LayoutSlot(x: CGFloat($0) * 0.25, y: 0, width: 0.25, height: 1)
    })

    public static let all: [LayoutDefinition] = [
        maximize, halves, split40_60, split60_40, split30_70, split70_30, topBottom,
        thirds, halfAndQuarters, wideCenter, twoThirdsOneThird, grid2x2, fourColumns,
    ]

    public static func layout(withID id: String) -> LayoutDefinition? {
        all.first { $0.id == id }
    }
}
