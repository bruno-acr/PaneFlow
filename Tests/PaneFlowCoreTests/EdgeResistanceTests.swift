import CoreGraphics
import XCTest
@testable import PaneFlowCore

/// MacBook (id 1) x 0…1470, y 0…956; LG (id 2) x −1920…0, y −351…729. Edge x = 0 shared for y ≤ 729.
final class EdgeResistanceTests: XCTestCase {
    let topology = Fixtures.realDevelopmentMac

    private func started(at point: CGPoint) -> EdgeResistance {
        var r = EdgeResistance()
        r.begin(at: point, topology: topology)
        return r
    }

    func testCursorIsHeldAtSharedEdge() {
        var r = started(at: CGPoint(x: 700, y: 400))
        XCTAssertNil(r.filter(CGPoint(x: 300, y: 400), topology: topology))
        // Crosses 12 pt into the LG: pulled back onto the MacBook's edge.
        XCTAssertEqual(r.filter(CGPoint(x: -12, y: 400), topology: topology), CGPoint(x: 0, y: 400))
        XCTAssertEqual(r.consumed, 12)
    }

    func testPushingLongEnoughBreaksThrough() {
        var r = started(at: CGPoint(x: 700, y: 400))
        var held = 0
        // The user keeps pushing 10 pt per sample against the edge.
        for _ in 0..<30 {
            if r.filter(CGPoint(x: -10, y: 400), topology: topology) != nil { held += 1 } else { break }
        }
        XCTAssertEqual(held, 13, "140 pt budget at 10 pt per sample")
        XCTAssertTrue(r.released)
        XCTAssertNil(r.filter(CGPoint(x: -30, y: 400), topology: topology))
    }

    func testFastFlickPassesAlmostImmediately() {
        var r = started(at: CGPoint(x: 700, y: 400))
        XCTAssertNil(r.filter(CGPoint(x: -400, y: 400), topology: topology), "one 400 pt sample exceeds the budget")
        XCTAssertTrue(r.released)
    }

    func testNewOriginAfterBreakingThroughAndRearm() {
        var r = started(at: CGPoint(x: 700, y: 400))
        _ = r.filter(CGPoint(x: -400, y: 400), topology: topology)
        // Well inside the LG: it becomes the origin, and its right edge now resists towards the MacBook.
        XCTAssertNil(r.filter(CGPoint(x: -900, y: 300), topology: topology))
        XCTAssertEqual(r.origin, 2)
        XCTAssertFalse(r.released)
        XCTAssertEqual(r.filter(CGPoint(x: 15, y: 300), topology: topology), CGPoint(x: -1, y: 300))
    }

    func testReturningInsideRearmsTheSameEdge() {
        var r = started(at: CGPoint(x: 700, y: 400))
        for _ in 0..<5 { _ = r.filter(CGPoint(x: -10, y: 400), topology: topology) }
        XCTAssertEqual(r.consumed, 50)
        _ = r.filter(CGPoint(x: 400, y: 400), topology: topology)
        XCTAssertEqual(r.consumed, 0)
    }

    func testOuterEdgesAndCornersAreNotTouched() {
        var r = started(at: CGPoint(x: 700, y: 800))
        // Below the LG the MacBook's left edge is a hard edge: the cursor cannot be outside; nothing to do.
        XCTAssertNil(r.filter(CGPoint(x: 0, y: 800), topology: topology))
        // A point diagonally past a corner is not a straight crossing.
        XCTAssertNil(r.filter(CGPoint(x: -10, y: -10), topology: topology))
        XCTAssertEqual(r.consumed, 0)
    }
}
