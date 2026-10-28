import CoreGraphics
import XCTest
@testable import PaneFlowCore

final class SnapAssistFillTests: XCTestCase {
    let area = CGRect(x: 0, y: 33, width: 1470, height: 849)

    func testNominalWhenFirstWindowIsExact() {
        let left = SnapRegion.leftHalf.frame(in: area)
        XCTAssertEqual(SnapAssistPlanner.fillFrame(for: .rightHalf, in: area, placed: [left]), SnapRegion.rightHalf.frame(in: area))
    }

    func testFillsWhatIsLeftWhenFirstWindowIsWider() {
        // The first app refused to be narrower than 900 pt: the second gets the remaining 570.
        let first = CGRect(x: 0, y: 33, width: 900, height: 849)
        XCTAssertEqual(SnapAssistPlanner.fillFrame(for: .rightHalf, in: area, placed: [first]),
                       CGRect(x: 900, y: 33, width: 570, height: 849))
    }

    func testFillsWhatIsLeftWhenFirstWindowIsNarrower() {
        // A 40/60 split made earlier: no hole is left.
        let first = CGRect(x: 0, y: 33, width: 588, height: 849)
        XCTAssertEqual(SnapAssistPlanner.fillFrame(for: .rightHalf, in: area, placed: [first]),
                       CGRect(x: 588, y: 33, width: 882, height: 849))
    }

    func testMirrorAndExternalDisplay() {
        let lg = CGRect(x: -1920, y: -321, width: 1920, height: 1050)
        let right = CGRect(x: -1100, y: -321, width: 1100, height: 1050)
        XCTAssertEqual(SnapAssistPlanner.fillFrame(for: .leftHalf, in: lg, placed: [right]),
                       CGRect(x: -1920, y: -321, width: 820, height: 1050))
    }

    func testGapIsRespected() {
        let spacing = LayoutSpacing(gap: 10, margin: 8)
        let first = CGRect(x: 8, y: 41, width: 700, height: 833)
        let frame = SnapAssistPlanner.fillFrame(for: .rightHalf, in: area, placed: [first], spacing: spacing)
        XCTAssertEqual(frame.minX, 718)
        XCTAssertEqual(frame.maxX, 1462)
    }

    func testQuarterUsesOnlyTheFacingNeighbour() {
        let topLeft = CGRect(x: 0, y: 33, width: 800, height: 424) // wider than its quarter
        let frame = SnapAssistPlanner.fillFrame(for: .topRightQuarter, in: area, placed: [topLeft])
        XCTAssertEqual(frame, CGRect(x: 800, y: 33, width: 670, height: SnapRegion.topRightQuarter.frame(in: area).height))
        // Bottom-left quarter: the top-left window is above it, so its top moves to that window's bottom.
        XCTAssertEqual(SnapAssistPlanner.fillFrame(for: .bottomLeftQuarter, in: area, placed: [topLeft]).minY, 457)
    }

    func testFloatingWindowsAreNotConsidered() {
        // Only windows placed in the layout are passed; with none, the nominal region is used.
        XCTAssertEqual(SnapAssistPlanner.fillFrame(for: .rightHalf, in: area, placed: []), SnapRegion.rightHalf.frame(in: area))
    }

    func testOverflowAnchorsToScreenEdgeAndTrimsNeighbour() {
        // Target 735 wide on the right, but Finder insists on 900.
        let target = CGRect(x: 735, y: 33, width: 735, height: 849)
        let actual = CGRect(x: 735, y: 33, width: 900, height: 849)
        let neighbour = WindowToken(rawValue: 1)
        let fix = SnapAssistPlanner.resolveOverflow(target: target, actual: actual, area: area,
                                                    neighbours: [neighbour: CGRect(x: 0, y: 33, width: 735, height: 849)])
        XCTAssertEqual(fix?.chosen, CGRect(x: 570, y: 33, width: 900, height: 849))
        XCTAssertEqual(fix?.neighbours[neighbour], CGRect(x: 0, y: 33, width: 570, height: 849))
    }

    func testOverflowOnTheLeft() {
        let target = CGRect(x: 0, y: 33, width: 735, height: 849)
        let actual = CGRect(x: 0, y: 33, width: 800, height: 849)
        let neighbour = WindowToken(rawValue: 2)
        let fix = SnapAssistPlanner.resolveOverflow(target: target, actual: actual, area: area,
                                                    neighbours: [neighbour: CGRect(x: 735, y: 33, width: 735, height: 849)])
        XCTAssertEqual(fix?.chosen, actual)
        XCTAssertEqual(fix?.neighbours[neighbour], CGRect(x: 800, y: 33, width: 670, height: 849))
    }

    func testNoOverflowNoCorrection() {
        let target = CGRect(x: 735, y: 33, width: 735, height: 849)
        XCTAssertNil(SnapAssistPlanner.resolveOverflow(target: target, actual: target, area: area, neighbours: [:]))
        // Smaller than the target (app maximum): left as is, never moved over a neighbour.
        XCTAssertNil(SnapAssistPlanner.resolveOverflow(target: target, actual: target.insetBy(dx: 20, dy: 0), area: area, neighbours: [:]))
    }
}
