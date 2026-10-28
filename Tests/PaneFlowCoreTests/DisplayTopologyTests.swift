import CoreGraphics
import XCTest
@testable import PaneFlowCore

final class DisplayTopologyTests: XCTestCase {
    func testPointLookupAcrossNegativeCoordinates() {
        let t = Fixtures.realDevelopmentMac
        XCTAssertEqual(t.display(containing: CGPoint(x: 100, y: 100))?.id, 1)
        XCTAssertEqual(t.display(containing: CGPoint(x: -100, y: -300))?.id, 2)
        XCTAssertEqual(t.display(containing: CGPoint(x: -1920, y: 728))?.id, 2)
    }

    func testPointInGapResolvesToNearestDisplay() {
        let t = Fixtures.realDevelopmentMac
        // Right of the built-in display, beyond any screen.
        XCTAssertEqual(t.display(containing: CGPoint(x: 1600, y: 500))?.id, 1)
        // Far above the external display.
        XCTAssertEqual(t.display(containing: CGPoint(x: -1000, y: -900))?.id, 2)
    }

    func testRectAssignedToDisplayWithLargestOverlap() {
        let t = Fixtures.realDevelopmentMac
        // Straddles the boundary, mostly on the external display.
        XCTAssertEqual(t.display(for: CGRect(x: -800, y: 100, width: 1000, height: 400))?.id, 2)
        // Mostly on the built-in display.
        XCTAssertEqual(t.display(for: CGRect(x: -200, y: 100, width: 1000, height: 400))?.id, 1)
        // Fully off-screen falls back to nearest.
        XCTAssertEqual(t.display(for: CGRect(x: 5000, y: 5000, width: 100, height: 100))?.id, 1)
    }

    func testStackedDisplays() {
        let t = Fixtures.stacked
        XCTAssertEqual(t.display(containing: CGPoint(x: 10, y: -10))?.id, 11)
        XCTAssertEqual(t.display(containing: CGPoint(x: 1600, y: 500))?.id, 12)
        XCTAssertEqual(t.primary?.id, 10)
    }

    func testNextDisplayCyclesLeftToRight() {
        let t = Fixtures.stacked
        // Ordered by minX: Above(-200), Primary(0), Right(1512).
        XCTAssertEqual(t.display(after: 11)?.id, 10)
        XCTAssertEqual(t.display(after: 10)?.id, 12)
        XCTAssertEqual(t.display(after: 12)?.id, 11)
        XCTAssertNil(DisplayTopology(displays: [t.displays[0]]).display(after: 10))
    }

    func testEmptyTopology() {
        let t = DisplayTopology(displays: [])
        XCTAssertNil(t.primary)
        XCTAssertNil(t.display(containing: .zero))
        XCTAssertNil(t.display(for: CGRect(x: 0, y: 0, width: 10, height: 10)))
    }
}
