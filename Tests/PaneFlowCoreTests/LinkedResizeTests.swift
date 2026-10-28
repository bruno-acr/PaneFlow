import CoreGraphics
import XCTest
@testable import PaneFlowCore

final class LinkedResizeTests: XCTestCase {
    let safari = WindowToken(rawValue: 1)
    let word = WindowToken(rawValue: 2)
    let left = CGRect(x: 0, y: 33, width: 735, height: 849)
    let right = CGRect(x: 735, y: 33, width: 735, height: 849)

    func testRightNeighbourIsPlanned() {
        let plan = LinkedResize.plan(driver: left, edge: .right, candidates: [.init(token: word, frame: right)])
        XCTAssertEqual(plan.followers, [.init(token: word, original: right, relation: .opposite)])
        XCTAssertTrue(LinkedResize.plan(driver: left, edge: .left, candidates: [.init(token: word, frame: right)]).isEmpty)
    }

    func testFiftyFiftyToFortySixty() {
        let plan = LinkedResize.plan(driver: left, edge: .right, candidates: [.init(token: word, frame: right)])
        let driverNow = CGRect(x: 0, y: 33, width: 588, height: 849) // 40 %
        let frames = LinkedResize.followerFrames(plans: [plan], driverOriginal: left, driverCurrent: driverNow)
        XCTAssertEqual(frames[word], CGRect(x: 588, y: 33, width: 882, height: 849))
    }

    func testDraggingLeftEdgeOfRightWindowMovesLeftNeighbour() {
        let plan = LinkedResize.plan(driver: right, edge: .left, candidates: [.init(token: safari, frame: left)])
        let driverNow = CGRect(x: 1029, y: 33, width: 441, height: 849) // Word 30 %
        let frames = LinkedResize.followerFrames(plans: [plan], driverOriginal: right, driverCurrent: driverNow)
        XCTAssertEqual(frames[safari], CGRect(x: 0, y: 33, width: 1029, height: 849))
    }

    func testGapIsPreserved() {
        let l = CGRect(x: 8, y: 41, width: 722, height: 833)
        let r = CGRect(x: 740, y: 41, width: 722, height: 833)
        let plan = LinkedResize.plan(driver: l, edge: .right, candidates: [.init(token: word, frame: r)])
        let frames = LinkedResize.followerFrames(plans: [plan], driverOriginal: l, driverCurrent: l.withMaxX(900))
        XCTAssertEqual(frames[word]?.minX, 910)
        XCTAssertEqual(frames[word]?.maxX, r.maxX)
    }

    func testFollowerIsClampedToMinimumLength() {
        let plan = LinkedResize.plan(driver: left, edge: .right, candidates: [.init(token: word, frame: right)])
        let frames = LinkedResize.followerFrames(plans: [plan], driverOriginal: left, driverCurrent: left.withMaxX(1460))
        XCTAssertEqual(frames[word]?.width, 160)
        XCTAssertEqual(frames[word]?.maxX, right.maxX)
    }

    func testUnrelatedWindowsAreIgnored() {
        let elsewhere = CGRect(x: 900, y: 300, width: 400, height: 300)  // floating, not touching
        let otherDisplay = CGRect(x: -960, y: -351, width: 960, height: 1080)
        let barelyOverlapping = CGRect(x: 735, y: 860, width: 735, height: 150)  // overlaps 22 pt: < 25 % of the shorter window
        let plan = LinkedResize.plan(driver: left, edge: .right, candidates: [
            .init(token: WindowToken(rawValue: 10), frame: elsewhere),
            .init(token: WindowToken(rawValue: 11), frame: otherDisplay),
            .init(token: WindowToken(rawValue: 12), frame: barelyOverlapping),
        ])
        XCTAssertTrue(plan.isEmpty)
    }

    func testGridDraggingVerticalDividerMovesAllFourWindows() {
        let tl = CGRect(x: 0, y: 33, width: 735, height: 424), tr = CGRect(x: 735, y: 33, width: 735, height: 424)
        let bl = CGRect(x: 0, y: 457, width: 735, height: 425), br = CGRect(x: 735, y: 457, width: 735, height: 425)
        let tokens = (tr: WindowToken(rawValue: 2), bl: WindowToken(rawValue: 3), br: WindowToken(rawValue: 4))
        let plan = LinkedResize.plan(driver: tl, edge: .right, candidates: [
            .init(token: tokens.tr, frame: tr), .init(token: tokens.bl, frame: bl), .init(token: tokens.br, frame: br),
        ])
        XCTAssertEqual(Set(plan.followers.map(\.token)), [tokens.tr, tokens.bl, tokens.br])
        let frames = LinkedResize.followerFrames(plans: [plan], driverOriginal: tl, driverCurrent: tl.withMaxX(600))
        XCTAssertEqual(frames[tokens.bl], bl.withMaxX(600), "stacked window follows the same edge")
        XCTAssertEqual(frames[tokens.tr], tr.withMinX(600))
        XCTAssertEqual(frames[tokens.br], br.withMinX(600))
    }

    func testHorizontalDividerTopBottom() {
        let top = CGRect(x: 0, y: 33, width: 1470, height: 424), bottom = CGRect(x: 0, y: 457, width: 1470, height: 425)
        let plan = LinkedResize.plan(driver: top, edge: .bottom, candidates: [.init(token: word, frame: bottom)])
        XCTAssertEqual(plan.followers.count, 1)
        let frames = LinkedResize.followerFrames(plans: [plan], driverOriginal: top, driverCurrent: top.withMaxY(600))
        XCTAssertEqual(frames[word], bottom.withMinY(600))
    }

    func testMovedEdges() {
        XCTAssertEqual(LinkedResize.movedEdges(original: left, current: left.withMaxX(600)), [.right])
        XCTAssertEqual(LinkedResize.movedEdges(original: right, current: right.withMinX(800)), [.left])
        XCTAssertEqual(LinkedResize.movedEdges(original: left, current: left.offsetBy(dx: 50, dy: 0)), [], "a move is not a resize")
        XCTAssertEqual(LinkedResize.movedEdges(original: left, current: left.withMaxX(600).withMaxY(700)), [.right, .bottom])
    }

    func testDriverCorrectionWhenFollowerRefusesToShrink() {
        let plan = LinkedResize.plan(driver: left, edge: .right, candidates: [.init(token: word, frame: right)])
        // User dragged to 1200, but Word stopped at minX 1000 (its minimum width).
        let corrected = LinkedResize.driverCorrection(plans: [plan], driverCurrent: left.withMaxX(1200),
                                                      followerActual: [word: right.withMinX(1000)])
        XCTAssertEqual(corrected, left.withMaxX(1000))
        XCTAssertNil(LinkedResize.driverCorrection(plans: [plan], driverCurrent: left.withMaxX(900),
                                                   followerActual: [word: right.withMinX(900)]))
    }
}
