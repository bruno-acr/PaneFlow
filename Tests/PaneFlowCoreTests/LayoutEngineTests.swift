import CoreGraphics
import XCTest
@testable import PaneFlowCore

final class LayoutEngineTests: XCTestCase {
    let builtInVisible = CGRect(x: 0, y: 33, width: 1470, height: 849)
    let externalVisible = CGRect(x: -1920, y: -351, width: 1920, height: 1080)

    func testAllCatalogLayoutsAreValid() throws {
        for layout in LayoutCatalog.all {
            XCTAssertNoThrow(try layout.validate(), layout.id)
        }
        XCTAssertEqual(Set(LayoutCatalog.all.map(\.id)).count, LayoutCatalog.all.count, "layout ids must be unique")
    }

    func testValidationRejectsOverlapAndOutOfBounds() {
        let overlapping = LayoutDefinition(id: "x", name: "x", slots: [
            LayoutSlot(x: 0, y: 0, width: 0.6, height: 1), LayoutSlot(x: 0.5, y: 0, width: 0.5, height: 1),
        ])
        XCTAssertThrowsError(try overlapping.validate()) { XCTAssertEqual($0 as? LayoutDefinition.ValidationError, .slotsOverlap(0, 1)) }
        let outside = LayoutDefinition(id: "y", name: "y", slots: [LayoutSlot(x: 0.5, y: 0, width: 0.6, height: 1)])
        XCTAssertThrowsError(try outside.validate())
        XCTAssertThrowsError(try LayoutDefinition(id: "z", name: "z", slots: []).validate())
    }

    func testHalvesOnOddWidthTileExactly() {
        let frames = LayoutEngine.frames(for: LayoutCatalog.halves, in: builtInVisible)
        XCTAssertEqual(frames[0], CGRect(x: 0, y: 33, width: 735, height: 849))
        XCTAssertEqual(frames[1], CGRect(x: 735, y: 33, width: 735, height: 849))
    }

    func testHalvesOnNegativeDisplay() {
        let frames = LayoutEngine.frames(for: LayoutCatalog.halves, in: externalVisible)
        XCTAssertEqual(frames[0], CGRect(x: -1920, y: -351, width: 960, height: 1080))
        XCTAssertEqual(frames[1], CGRect(x: -960, y: -351, width: 960, height: 1080))
    }

    func testRatiosProduceRequestedProportions() {
        let f = LayoutEngine.frames(for: LayoutCatalog.split40_60, in: externalVisible)
        XCTAssertEqual(f[0].width, 768)
        XCTAssertEqual(f[1].width, 1152)
        XCTAssertEqual(f[0].maxX, f[1].minX)
        let g = LayoutEngine.frames(for: LayoutCatalog.split70_30, in: externalVisible)
        XCTAssertEqual(g[0].width, 1344)
        XCTAssertEqual(g[1].width, 576)
    }

    func testEveryLayoutCoversAreaWithoutOverlapOrSlivers() {
        let areas = [builtInVisible, externalVisible, CGRect(x: 1512, y: 125, width: 1921, height: 999)]
        for area in areas {
            for layout in LayoutCatalog.all {
                let frames = LayoutEngine.frames(for: layout, in: area)
                XCTAssertEqual(frames.count, layout.slots.count)
                let covered = frames.reduce(0) { $0 + $1.area }
                XCTAssertEqual(covered, area.area, accuracy: 0.5, "\(layout.id) must cover \(area)")
                for (i, a) in frames.enumerated() {
                    XCTAssertTrue(area.contains(a), "\(layout.id) slot \(i) escapes area")
                    XCTAssertEqual(a, a.integral, "\(layout.id) slot \(i) must be integral")
                    for b in frames[(i + 1)...] {
                        XCTAssertEqual(a.intersectionArea(with: b), 0, "\(layout.id) slots overlap")
                    }
                }
            }
        }
    }

    func testGapsAndMargins() {
        let spacing = LayoutSpacing(gap: 10, margin: 8)
        let f = LayoutEngine.frames(for: LayoutCatalog.halves, in: builtInVisible, spacing: spacing)
        XCTAssertEqual(f[0].minX, 8)
        XCTAssertEqual(f[0].minY, 41)
        XCTAssertEqual(f[1].maxX, 1462)
        XCTAssertEqual(f[1].minX - f[0].maxX, 10, "gap between windows")
        XCTAssertEqual(f[0].height, 849 - 16)

        let grid = LayoutEngine.frames(for: LayoutCatalog.grid2x2, in: externalVisible, spacing: spacing)
        XCTAssertEqual(grid[2].minY - grid[0].maxY, 10)
        XCTAssertEqual(grid[1].minX - grid[0].maxX, 10)
        XCTAssertEqual(grid[0].width, grid[1].width)
    }

    func testNegativeSpacingIsClampedAndOversizedMarginYieldsEmptyFrames() {
        XCTAssertEqual(LayoutSpacing(gap: -5, margin: -3), .none)
        let frames = LayoutEngine.frames(for: LayoutCatalog.halves, in: CGRect(x: 0, y: 0, width: 100, height: 100),
                                         spacing: LayoutSpacing(margin: 60))
        XCTAssertEqual(frames, [.zero, .zero])
    }

    func testCenteredClampsToArea() {
        let area = builtInVisible
        XCTAssertEqual(LayoutEngine.centered(size: CGSize(width: 400, height: 300), in: area),
                       CGRect(x: 535, y: 308, width: 400, height: 300))
        let huge = LayoutEngine.centered(size: CGSize(width: 5000, height: 5000), in: area)
        XCTAssertEqual(huge, area)
    }

    func testCatalogLookup() {
        XCTAssertEqual(LayoutCatalog.layout(withID: "split-40-60"), LayoutCatalog.split40_60)
        XCTAssertNil(LayoutCatalog.layout(withID: "nope"))
    }
}
