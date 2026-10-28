import CoreGraphics
import XCTest
@testable import PaneFlowCore

final class SnapAssistPlannerTests: XCTestCase {
    let area = CGRect(x: 0, y: 33, width: 1470, height: 849)

    func testHalvesOfferTheOppositeHalf() {
        XCTAssertEqual(SnapAssistPlanner.emptyRegions(after: .leftHalf, in: area, occupied: []), [.rightHalf])
        XCTAssertEqual(SnapAssistPlanner.emptyRegions(after: .topHalf, in: area, occupied: []), [.bottomHalf])
        XCTAssertEqual(SnapAssistPlanner.emptyRegions(after: .maximize, in: area, occupied: []), [])
    }

    func testOccupiedRegionsAreSkipped() {
        let right = SnapRegion.rightHalf.frame(in: area)
        XCTAssertEqual(SnapAssistPlanner.emptyRegions(after: .leftHalf, in: area, occupied: [right]), [])
        // Close enough (app rounding) still counts as occupied.
        XCTAssertEqual(SnapAssistPlanner.emptyRegions(after: .leftHalf, in: area, occupied: [right.insetBy(dx: 4, dy: 3)]), [])
        // A floating window over there does not.
        XCTAssertEqual(SnapAssistPlanner.emptyRegions(after: .leftHalf, in: area, occupied: [CGRect(x: 900, y: 200, width: 400, height: 300)]), [.rightHalf])
    }

    func testQuarterOffersTheOtherThree() {
        let topRight = SnapRegion.topRightQuarter.frame(in: area)
        XCTAssertEqual(SnapAssistPlanner.emptyRegions(after: .topLeftQuarter, in: area, occupied: [topRight]),
                       [.bottomLeftQuarter, .bottomRightQuarter])
    }
}

final class TileArrangementTests: XCTestCase {
    let area = CGRect(x: 0, y: 33, width: 1470, height: 849)
    let a = WindowToken(rawValue: 1), b = WindowToken(rawValue: 2), c = WindowToken(rawValue: 3), far = WindowToken(rawValue: 9)

    func testSwapHalves() {
        let left = CGRect(x: 0, y: 33, width: 735, height: 849), right = CGRect(x: 735, y: 33, width: 735, height: 849)
        let windows = [LinkedResize.Candidate(token: a, frame: left), .init(token: b, frame: right),
                       .init(token: far, frame: CGRect(x: -1500, y: 0, width: 600, height: 400))]
        let group = TileArrangement.connectedGroup(from: a, windows: windows)
        XCTAssertEqual(Set(group.map(\.token)), [a, b])
        XCTAssertEqual(TileArrangement.swapAxis(for: group), .horizontal)
        let result = TileArrangement.mirrored(group, in: area, axis: .horizontal)
        XCTAssertEqual(result[a], right)
        XCTAssertEqual(result[b], left)
    }

    func testSwapKeepsProportions() {
        // Safari 30 % | Word 70 %  →  Word 70 % | Safari 30 %
        let s = CGRect(x: 0, y: 33, width: 441, height: 849), w = CGRect(x: 441, y: 33, width: 1029, height: 849)
        let result = TileArrangement.mirrored([.init(token: a, frame: s), .init(token: b, frame: w)], in: area, axis: .horizontal)
        XCTAssertEqual(result[b], CGRect(x: 0, y: 33, width: 1029, height: 849))
        XCTAssertEqual(result[a], CGRect(x: 1029, y: 33, width: 441, height: 849))
    }

    func testThreeColumnsReverse() {
        let cols = LayoutEngine.frames(for: LayoutCatalog.thirds, in: area)
        let windows = zip([a, b, c], cols).map { LinkedResize.Candidate(token: $0, frame: $1) }
        let group = TileArrangement.connectedGroup(from: b, windows: windows)
        XCTAssertEqual(group.count, 3)
        let result = TileArrangement.mirrored(group, in: area, axis: .horizontal)
        XCTAssertEqual(result[a], cols[2])
        XCTAssertEqual(result[c], cols[0])
        XCTAssertEqual(result[b], cols[1])
    }

    func testStackedWindowsSwapVertically() {
        let top = SnapRegion.topHalf.frame(in: area), bottom = SnapRegion.bottomHalf.frame(in: area)
        let group = TileArrangement.connectedGroup(from: a, windows: [.init(token: a, frame: top), .init(token: b, frame: bottom)])
        XCTAssertEqual(TileArrangement.swapAxis(for: group), .vertical)
        let result = TileArrangement.mirrored(group, in: area, axis: .vertical)
        // Sizes are preserved (424 vs 425 pt halves), so the windows exchange places exactly.
        XCTAssertEqual(result[a], CGRect(x: 0, y: bottom.maxY - top.height, width: 1470, height: top.height))
        XCTAssertEqual(result[b], CGRect(x: 0, y: top.minY, width: 1470, height: bottom.height))
    }

    func testSingleWindowMirrorsAcrossTheScreen() {
        let left = SnapRegion.leftHalf.frame(in: area)
        let result = TileArrangement.mirrored([.init(token: a, frame: left)], in: area, axis: .horizontal)
        XCTAssertEqual(result[a], SnapRegion.rightHalf.frame(in: area))
    }

    func testUnknownStartGivesEmptyGroup() {
        XCTAssertTrue(TileArrangement.connectedGroup(from: far, windows: []).isEmpty)
    }
}
