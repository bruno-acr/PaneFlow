import CoreGraphics
import XCTest
@testable import PaneFlowCore

final class WindowEligibilityTests: XCTestCase {
    private func window(
        pid: Int32 = 100, role: String? = "AXWindow", subrole: String? = "AXStandardWindow",
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
        minimized: Bool = false, movable: Bool = true, resizable: Bool = true
    ) -> WindowSnapshot {
        WindowSnapshot(token: WindowToken(rawValue: 1), pid: pid, bundleIdentifier: "com.example", applicationName: "Example",
                       title: "Doc", role: role, subrole: subrole, frame: frame, isMinimized: minimized,
                       isMovable: movable, isResizable: resizable, isMain: true, isFocused: true)
    }

    let policy = WindowEligibilityPolicy(ownProcessID: 1)

    func testStandardWindowIsEligible() {
        XCTAssertEqual(policy.evaluate(window()), .eligible(resizable: true))
        XCTAssertEqual(policy.evaluate(window(resizable: false)), .eligible(resizable: false))
    }

    func testRejections() {
        XCTAssertEqual(policy.evaluate(window(role: "AXSheet")), .ineligible(.notAWindow))
        XCTAssertEqual(policy.evaluate(window(subrole: "AXDialog")), .ineligible(.nonStandardSubrole))
        XCTAssertEqual(policy.evaluate(window(subrole: "AXFloatingWindow")), .ineligible(.nonStandardSubrole))
        XCTAssertEqual(policy.evaluate(window(subrole: nil)), .ineligible(.nonStandardSubrole))
        XCTAssertEqual(policy.evaluate(window(minimized: true)), .ineligible(.minimized))
        XCTAssertEqual(policy.evaluate(window(movable: false)), .ineligible(.notMovable))
        XCTAssertEqual(policy.evaluate(window(frame: CGRect(x: 0, y: 0, width: 30, height: 30))), .ineligible(.tooSmall))
        XCTAssertEqual(policy.evaluate(window(pid: 1)), .ineligible(.ownedByPaneFlow))
    }
}

final class WindowIdentityResolverTests: XCTestCase {
    let resolver = WindowIdentityResolver()
    let frameA = CGRect(x: 0, y: 33, width: 735, height: 849)
    let frameB = CGRect(x: 735, y: 33, width: 735, height: 849)

    private func ax(_ token: UInt64, pid: Int32, _ frame: CGRect, _ title: String?) -> AccessibilityWindowSignal {
        AccessibilityWindowSignal(token: WindowToken(rawValue: token), pid: pid, frame: frame, title: title)
    }

    private func server(_ id: UInt32, pid: Int32, _ frame: CGRect, _ title: String?, layer: Int = 0, order: Int = 0) -> ServerWindowSignal {
        ServerWindowSignal(windowID: id, pid: pid, frame: frame, title: title, layer: layer, stackingOrder: order)
    }

    func testUniqueMatchByPidAndFrameWithoutTitles() {
        let r = resolver.correlate([ax(1, pid: 10, frameA, "Doc 1"), ax(2, pid: 20, frameB, "Page")],
                                   with: [server(100, pid: 10, frameA, nil, order: 1), server(200, pid: 20, frameB, nil, order: 0)])
        XCTAssertEqual(r[WindowToken(rawValue: 1)], .unique(windowID: 100, stackingOrder: 1))
        XCTAssertEqual(r[WindowToken(rawValue: 2)], .unique(windowID: 200, stackingOrder: 0))
    }

    func testFrameToleranceAbsorbsRounding() {
        let r = resolver.correlate([ax(1, pid: 10, frameA, nil)],
                                   with: [server(100, pid: 10, frameA.offsetBy(dx: 1.5, dy: -1), nil)])
        XCTAssertEqual(r[WindowToken(rawValue: 1)], .unique(windowID: 100, stackingOrder: 0))
    }

    func testSamePidSameFrameWithoutTitlesIsAmbiguous() {
        // Two Word documents stacked exactly on top of each other, no Screen Recording permission.
        let r = resolver.correlate([ax(1, pid: 10, frameA, "Report.docx"), ax(2, pid: 10, frameA, "Budget.docx")],
                                   with: [server(100, pid: 10, frameA, nil), server(101, pid: 10, frameA, nil)])
        XCTAssertEqual(r[WindowToken(rawValue: 1)], .ambiguous(windowIDs: [100, 101]))
        XCTAssertEqual(r[WindowToken(rawValue: 2)], .ambiguous(windowIDs: [100, 101]))
    }

    func testTitlesDisambiguateWhenAvailable() {
        let r = resolver.correlate([ax(1, pid: 10, frameA, "Report.docx"), ax(2, pid: 10, frameA, "Budget.docx")],
                                   with: [server(100, pid: 10, frameA, "Budget.docx"), server(101, pid: 10, frameA, "Report.docx")])
        XCTAssertEqual(r[WindowToken(rawValue: 1)], .unique(windowID: 101, stackingOrder: 0))
        XCTAssertEqual(r[WindowToken(rawValue: 2)], .unique(windowID: 100, stackingOrder: 0))
    }

    func testIdenticalTitlesAndFramesStayAmbiguous() {
        let r = resolver.correlate([ax(1, pid: 10, frameA, "Untitled"), ax(2, pid: 10, frameA, "Untitled")],
                                   with: [server(100, pid: 10, frameA, "Untitled"), server(101, pid: 10, frameA, "Untitled")])
        XCTAssertEqual(r[WindowToken(rawValue: 1)], .ambiguous(windowIDs: [100, 101]))
    }

    func testTwoAXWindowsClaimingOneServerWindowAreAmbiguous() {
        let r = resolver.correlate([ax(1, pid: 10, frameA, nil), ax(2, pid: 10, frameA, nil)],
                                   with: [server(100, pid: 10, frameA, nil)])
        XCTAssertEqual(r[WindowToken(rawValue: 1)], .ambiguous(windowIDs: [100]))
        XCTAssertEqual(r[WindowToken(rawValue: 2)], .ambiguous(windowIDs: [100]))
    }

    func testDifferentPidOrNonZeroLayerNeverMatches() {
        let r = resolver.correlate([ax(1, pid: 10, frameA, nil)],
                                   with: [server(100, pid: 11, frameA, nil), server(101, pid: 10, frameA, nil, layer: 25)])
        XCTAssertEqual(r[WindowToken(rawValue: 1)], WindowCorrelation.none)
    }

    func testOffScreenWindowHasNoMatch() {
        let r = resolver.correlate([ax(1, pid: 10, frameA, "x")], with: [])
        XCTAssertEqual(r[WindowToken(rawValue: 1)], WindowCorrelation.none)
    }
}

final class GeometryVerifierTests: XCTestCase {
    let requested = CGRect(x: 0, y: 33, width: 735, height: 849)

    func testExactWithinOnePoint() {
        XCTAssertEqual(GeometryVerifier.verify(requested: requested, actual: requested.offsetBy(dx: 1, dy: 0)), .exact)
    }

    func testAppImposedSizeIsAdjustment() {
        // Terminal rounding to character cells.
        let actual = CGRect(x: 0, y: 33, width: 729, height: 842)
        XCTAssertEqual(GeometryVerifier.verify(requested: requested, actual: actual),
                       .adjustedByApplication(requested: requested, actual: actual))
        // Minimum width larger than the slot.
        let wider = CGRect(x: 0, y: 33, width: 900, height: 849)
        XCTAssertTrue(GeometryVerifier.verify(requested: requested, actual: wider).isAcceptable)
    }

    func testWindowThatDidNotMoveFails() {
        let actual = CGRect(x: 600, y: 300, width: 500, height: 400)
        XCTAssertEqual(GeometryVerifier.verify(requested: requested, actual: actual), .failed(requested: requested, actual: actual))
        XCTAssertFalse(GeometryVerifier.verify(requested: requested, actual: actual).isAcceptable)
    }
}

final class LatencyStatisticsTests: XCTestCase {
    func testPercentiles() {
        var s = LatencyStatistics(capacity: 100)
        XCTAssertNil(s.p50)
        for v in 1...100 { s.record(Double(v)) }
        XCTAssertEqual(s.p50, 50)
        XCTAssertEqual(s.p95, 95)
        XCTAssertEqual(s.percentile(100), 100)
        XCTAssertEqual(s.percentile(0), 1)
    }

    func testCapacityIsBounded() {
        var s = LatencyStatistics(capacity: 10)
        for v in 1...1000 { s.record(Double(v)) }
        XCTAssertEqual(s.samples.count, 10)
        XCTAssertEqual(s.totalCount, 1000)
        XCTAssertEqual(s.samples.min(), 991, "only the most recent samples are kept")
    }
}
