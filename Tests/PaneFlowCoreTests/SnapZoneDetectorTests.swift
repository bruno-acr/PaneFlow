import CoreGraphics
import XCTest
@testable import PaneFlowCore

/// Uses the real development topology: LG (id 2) at x −1920…0, y −351…729; MacBook (id 1) at x 0…1470, y 0…956.
/// The edge x = 0 is shared for y in 0…729 and an outer edge below y = 729.
final class SnapZoneDetectorTests: XCTestCase {
    let detector = SnapZoneDetector(topology: Fixtures.realDevelopmentMac)

    private func zone(_ region: SnapRegion, _ display: UInt32, shared: Bool = false) -> ZoneCandidate {
        ZoneCandidate(zone: SnapZone(region: region, displayID: display), onSharedEdge: shared)
    }

    func testOuterEdgesOfBuiltIn() {
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: 1468, y: 500)), zone(.rightHalf, 1))
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: 700, y: 2)), zone(.maximize, 1))
        XCTAssertNil(detector.detect(cursor: CGPoint(x: 700, y: 500)))
        XCTAssertNil(detector.detect(cursor: CGPoint(x: 1460, y: 500)), "beyond the outer threshold")
    }

    func testSharedEdgeOnBothSides() {
        // Just inside the MacBook, next to the LG: MacBook left half, flagged as shared.
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: 10, y: 400)), zone(.leftHalf, 1, shared: true))
        // Just inside the LG, next to the MacBook: LG right half, flagged as shared.
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: -10, y: 300)), zone(.rightHalf, 2, shared: true))
        // Shared bands (40 pt) are wider than outer edges but still bounded.
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: 38, y: 400)), zone(.leftHalf, 1, shared: true))
        XCTAssertNil(detector.detect(cursor: CGPoint(x: 60, y: 400)))
        XCTAssertNil(detector.detect(cursor: CGPoint(x: -60, y: 300)))
    }

    func testOvershootBelongsToApproachDisplay() {
        // Dragging from the MacBook, the cursor slips 30 pt into the LG: still the MacBook's left half.
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: -30, y: 400), approach: 1), zone(.leftHalf, 1, shared: true))
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: -75, y: 400), approach: 1), zone(.leftHalf, 1, shared: true))
        // Far into the LG: no zone (the user is moving the window to the other display).
        XCTAssertNil(detector.detect(cursor: CGPoint(x: -300, y: 400), approach: 1))
        // Coming from the LG and slipping into the MacBook: the LG's right half.
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: 30, y: 400), approach: 2), zone(.rightHalf, 2, shared: true))
        // Overshoot never applies across an outer edge segment (below the LG the MacBook edge is a hard edge).
        XCTAssertNil(detector.detect(cursor: CGPoint(x: 30, y: 800), approach: 2))
    }

    func testSharedBandMembership() {
        XCTAssertTrue(detector.isNearSharedEdge(CGPoint(x: 50, y: 400)))
        XCTAssertTrue(detector.isNearSharedEdge(CGPoint(x: -50, y: 400)))
        XCTAssertFalse(detector.isNearSharedEdge(CGPoint(x: 700, y: 400)))
        XCTAssertFalse(detector.isNearSharedEdge(CGPoint(x: 50, y: 900)), "below the LG the edge is not shared")
    }

    func testEdgeBecomesOuterWhereNoDisplayContinues() {
        // Below the LG's bottom (y > 729) the MacBook's left edge is a hard edge.
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: 3, y: 800)), zone(.leftHalf, 1))
        XCTAssertNil(detector.detect(cursor: CGPoint(x: 10, y: 800)), "outer threshold is narrower")
    }

    func testOuterEdgesOfExternalDisplay() {
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: -1918, y: 200)), zone(.leftHalf, 2))
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: -900, y: -349)), zone(.maximize, 2))
    }

    func testCornersSelectQuarters() {
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: 1469, y: 10)), zone(.topRightQuarter, 1))
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: 1469, y: 950)), zone(.bottomRightQuarter, 1))
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: 1400, y: 1)), zone(.topRightQuarter, 1))
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: -1919, y: -340)), zone(.topLeftQuarter, 2))
        XCTAssertEqual(detector.detect(cursor: CGPoint(x: -1900, y: 727)), zone(.bottomLeftQuarter, 2))
        XCTAssertNil(detector.detect(cursor: CGPoint(x: 700, y: 954)), "bottom edge centre has no zone")
    }

    func testHysteresisKeepsActiveZone() {
        let active = zone(.rightHalf, 1)
        let slightlyOut = CGPoint(x: 1450, y: 500) // 20 pt from the edge: outside 6 pt, inside 6+24
        XCTAssertNil(detector.detect(cursor: slightlyOut))
        XCTAssertEqual(detector.detect(cursor: slightlyOut, current: active), active)
        XCTAssertNil(detector.detect(cursor: CGPoint(x: 1400, y: 500), current: active))
    }

    func testDisabledOptions() {
        var settings = SnapZoneSettings()
        settings.topEdgeMaximizes = false
        settings.cornersSnapToQuarters = false
        let d = SnapZoneDetector(topology: Fixtures.realDevelopmentMac, settings: settings)
        XCTAssertNil(d.detect(cursor: CGPoint(x: 700, y: 2)))
        XCTAssertEqual(d.detect(cursor: CGPoint(x: 1469, y: 10)), zone(.rightHalf, 1))
    }

    func testZoneFrames() {
        let t = Fixtures.realDevelopmentMac
        XCTAssertEqual(SnapZone(region: .rightHalf, displayID: 2).frame(in: t), CGRect(x: -960, y: -351, width: 960, height: 1080))
        XCTAssertEqual(SnapZone(region: .leftHalf, displayID: 1).frame(in: t), CGRect(x: 0, y: 33, width: 735, height: 849))
        XCTAssertNil(SnapZone(region: .leftHalf, displayID: 99).frame(in: t))
    }
}

final class SnapStateMachineTests: XCTestCase {
    let window = WindowToken(rawValue: 7)

    private func machine(_ timing: SnapTiming = SnapTiming()) -> SnapStateMachine {
        SnapStateMachine(detector: SnapZoneDetector(topology: Fixtures.realDevelopmentMac), timing: timing)
    }

    private let rightEdge = CGPoint(x: 1469, y: 500)
    private var rightZone: SnapZone { SnapZone(region: .rightHalf, displayID: 1) }

    func testOuterEdgePreviewsImmediatelyAndCommitsOnRelease() {
        var m = machine()
        XCTAssertEqual(m.handle(.dragStarted(session: 1, window: window, cursor: CGPoint(x: 700, y: 400), time: 0)), [])
        XCTAssertEqual(m.handle(.cursorMoved(rightEdge, time: 0.1)), [.showPreview(rightZone)])
        XCTAssertEqual(m.handle(.cursorMoved(CGPoint(x: 1468, y: 520), time: 0.12)), [], "same zone: no duplicate effect")
        XCTAssertEqual(m.handle(.mouseReleased), [.hidePreview, .commit(session: 1, window: window, zone: rightZone)])
        XCTAssertEqual(m.state, .committing(session: 1, window: window, zone: rightZone))
        XCTAssertEqual(m.handle(.commitFinished(session: 1)), [])
        XCTAssertEqual(m.state, .idle)
    }

    func testReleaseOutsideZoneDoesNothing() {
        var m = machine()
        _ = m.handle(.dragStarted(session: 1, window: window, cursor: CGPoint(x: 700, y: 400), time: 0))
        _ = m.handle(.cursorMoved(rightEdge, time: 0.1))
        XCTAssertEqual(m.handle(.cursorMoved(CGPoint(x: 700, y: 400), time: 0.2)), [.hidePreview])
        XCTAssertEqual(m.handle(.mouseReleased), [])
        XCTAssertEqual(m.state, .idle)
    }

    func testSharedEdgeRequiresDwell() {
        var m = machine(SnapTiming(activationDelay: 0, sharedEdgeDelay: 0.3))
        _ = m.handle(.dragStarted(session: 1, window: window, cursor: CGPoint(x: 700, y: 400), time: 0))
        let shared = CGPoint(x: 8, y: 400)
        let leftZone = SnapZone(region: .leftHalf, displayID: 1)
        XCTAssertEqual(m.handle(.cursorMoved(shared, time: 1.0)), [])
        XCTAssertEqual(m.handle(.tick(time: 1.2)), [], "not yet")
        XCTAssertEqual(m.handle(.tick(time: 1.31)), [.showPreview(leftZone)])
        XCTAssertEqual(m.handle(.mouseReleased), [.hidePreview, .commit(session: 1, window: window, zone: leftZone)])
    }

    func testDraggingFromMacBookAndOvershootingSnapsToMacBookLeftHalf() {
        var m = machine()
        _ = m.handle(.dragStarted(session: 1, window: window, cursor: CGPoint(x: 700, y: 400), time: 0))
        _ = m.handle(.cursorMoved(CGPoint(x: 300, y: 400), time: 0.1))
        XCTAssertEqual(m.approachDisplay, 1)
        // The cursor slips 25 pt into the LG and rests there.
        XCTAssertEqual(m.handle(.cursorMoved(CGPoint(x: -25, y: 400), time: 0.2)), [])
        let macLeft = SnapZone(region: .leftHalf, displayID: 1)
        XCTAssertEqual(m.handle(.tick(time: 0.45)), [.showPreview(macLeft)])
        XCTAssertEqual(m.approachDisplay, 1, "approach is not updated inside the band")
        XCTAssertEqual(m.handle(.mouseReleased), [.hidePreview, .commit(session: 1, window: window, zone: macLeft)])
    }

    func testMovingDeepIntoOtherDisplayChangesApproach() {
        var m = machine()
        _ = m.handle(.dragStarted(session: 1, window: window, cursor: CGPoint(x: 700, y: 400), time: 0))
        _ = m.handle(.cursorMoved(CGPoint(x: -900, y: 300), time: 0.1))
        XCTAssertEqual(m.approachDisplay, 2)
        _ = m.handle(.cursorMoved(CGPoint(x: 20, y: 300), time: 0.2))
        XCTAssertEqual(m.handle(.tick(time: 0.45)), [.showPreview(SnapZone(region: .rightHalf, displayID: 2))])
    }

    func testCrossingSharedEdgeQuicklyNeverSnaps() {
        var m = machine()
        _ = m.handle(.dragStarted(session: 1, window: window, cursor: CGPoint(x: 300, y: 400), time: 0))
        var effects: [SnapEffect] = []
        // Fast drag from the MacBook to the middle of the LG, 10 ms per sample.
        for (i, x) in stride(from: 300.0, through: -900.0, by: -40.0).enumerated() {
            effects += m.handle(.cursorMoved(CGPoint(x: x, y: 400), time: Double(i) * 0.01))
        }
        effects += m.handle(.tick(time: 0.5))
        XCTAssertEqual(effects, [])
        XCTAssertEqual(m.handle(.mouseReleased), [])
    }

    func testCancelHidesPreviewAndIgnoresRestOfGesture() {
        var m = machine()
        _ = m.handle(.dragStarted(session: 3, window: window, cursor: rightEdge, time: 0))
        XCTAssertEqual(m.state, .previewing(session: 3, window: window, zone: ZoneCandidate(zone: rightZone, onSharedEdge: false)))
        XCTAssertEqual(m.handle(.cancel), [.hidePreview])
        XCTAssertEqual(m.handle(.cursorMoved(rightEdge, time: 1)), [])
        XCTAssertEqual(m.handle(.cancel), [], "repeated Escape is harmless")
        XCTAssertEqual(m.handle(.mouseReleased), [])
        XCTAssertEqual(m.state, .idle)
    }

    func testSuppressionModifier() {
        var m = machine()
        _ = m.handle(.dragStarted(session: 1, window: window, cursor: CGPoint(x: 700, y: 400), time: 0))
        _ = m.handle(.cursorMoved(rightEdge, time: 0.1))
        XCTAssertEqual(m.handle(.suppression(true)), [.hidePreview])
        XCTAssertEqual(m.handle(.cursorMoved(rightEdge, time: 0.2)), [])
        XCTAssertEqual(m.handle(.suppression(false)), [.showPreview(rightZone)])
    }

    func testStaleCommitFinishedIsIgnoredAndNoConcurrentSnaps() {
        var m = machine()
        _ = m.handle(.dragStarted(session: 1, window: window, cursor: rightEdge, time: 0))
        _ = m.handle(.mouseReleased)
        XCTAssertEqual(m.handle(.dragStarted(session: 2, window: window, cursor: rightEdge, time: 1)), [], "busy committing")
        XCTAssertEqual(m.handle(.commitFinished(session: 99)), [])
        XCTAssertEqual(m.state.session, 1)
        _ = m.handle(.commitFinished(session: 1))
        XCTAssertEqual(m.state, .idle)
    }

    func testNewGestureSupersedesStaleOne() {
        var m = machine()
        _ = m.handle(.dragStarted(session: 1, window: window, cursor: rightEdge, time: 0))
        let other = WindowToken(rawValue: 8)
        XCTAssertEqual(m.handle(.dragStarted(session: 2, window: other, cursor: CGPoint(x: 700, y: 400), time: 1)), [.hidePreview])
        XCTAssertEqual(m.state, .trackingDrag(session: 2, window: other))
    }

    func testSwitchingZonesUpdatesPreview() {
        var m = machine()
        _ = m.handle(.dragStarted(session: 1, window: window, cursor: rightEdge, time: 0))
        XCTAssertEqual(m.handle(.cursorMoved(CGPoint(x: 1469, y: 10), time: 0.1)), [.showPreview(SnapZone(region: .topRightQuarter, displayID: 1))])
    }
}

final class SnapCyclingTests: XCTestCase {
    let t = Fixtures.realDevelopmentMac
    let macLeft = CGRect(x: 0, y: 33, width: 735, height: 849)
    let macRight = CGRect(x: 735, y: 33, width: 735, height: 849)

    func testFloatingWindowSnapsOnItsDisplay() {
        XCTAssertEqual(SnapCycling.target(direction: .left, windowFrame: CGRect(x: 200, y: 200, width: 600, height: 400), topology: t),
                       SnapZone(region: .leftHalf, displayID: 1))
    }

    func testLeftFromLeftHalfCrossesToNeighbourDisplay() {
        XCTAssertEqual(SnapCycling.target(direction: .left, windowFrame: macLeft, topology: t),
                       SnapZone(region: .rightHalf, displayID: 2))
    }

    func testLeftFromRightHalfGoesToLeftHalf() {
        XCTAssertEqual(SnapCycling.target(direction: .left, windowFrame: macRight, topology: t),
                       SnapZone(region: .leftHalf, displayID: 1))
    }

    func testRightFromExternalRightHalfComesBackToBuiltIn() {
        let lgRight = CGRect(x: -960, y: -351, width: 960, height: 1080)
        XCTAssertEqual(SnapCycling.target(direction: .right, windowFrame: lgRight, topology: t),
                       SnapZone(region: .leftHalf, displayID: 1))
    }

    func testNoDisplayBeyondTheEdge() {
        let lgLeft = CGRect(x: -1920, y: -351, width: 960, height: 1080)
        XCTAssertNil(SnapCycling.target(direction: .left, windowFrame: lgLeft, topology: t))
        XCTAssertNil(SnapCycling.target(direction: .right, windowFrame: macRight, topology: t))
    }

    func testToleratesAppRounding() {
        let terminalLike = CGRect(x: 0, y: 33, width: 729, height: 840)
        XCTAssertEqual(SnapCycling.target(direction: .left, windowFrame: terminalLike, topology: t),
                       SnapZone(region: .rightHalf, displayID: 2))
    }

    func testAdjacentDisplayLookup() {
        XCTAssertEqual(t.display(adjacentTo: 1, direction: .left)?.id, 2)
        XCTAssertEqual(t.display(adjacentTo: 2, direction: .right)?.id, 1)
        XCTAssertNil(t.display(adjacentTo: 1, direction: .right))
        let s = Fixtures.stacked
        XCTAssertEqual(s.display(adjacentTo: 10, direction: .up)?.id, 11)
        XCTAssertEqual(s.display(adjacentTo: 10, direction: .right)?.id, 12)
    }
}
