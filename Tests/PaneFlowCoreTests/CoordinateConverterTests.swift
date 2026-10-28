import CoreGraphics
import XCTest
@testable import PaneFlowCore

final class CoordinateConverterTests: XCTestCase {
    func testPrimaryDisplayMapsToOrigin() {
        let global = Fixtures.converter.globalRect(fromAppKit: Fixtures.builtInAppKit)
        XCTAssertEqual(global, CGRect(x: 0, y: 0, width: 1470, height: 956))
    }

    func testVisibleFrameExcludesMenuBarAtTopAndDockAtBottom() {
        // AppKit visible frame starts 74 pt above the bottom (Dock) and ends 33 pt below the top (menu bar).
        let global = Fixtures.converter.globalRect(fromAppKit: Fixtures.builtInVisibleAppKit)
        XCTAssertEqual(global, CGRect(x: 0, y: 33, width: 1470, height: 849))
    }

    func testExternalDisplayLeftAndAboveHasNegativeGlobalOrigin() {
        let global = Fixtures.converter.globalRect(fromAppKit: Fixtures.externalAppKit)
        XCTAssertEqual(global, CGRect(x: -1920, y: -351, width: 1920, height: 1080))
    }

    func testRoundTripIsIdentity() {
        let rects = [
            CGRect(x: -1920, y: -351, width: 1920, height: 1080),
            CGRect(x: 12.5, y: 400.25, width: 300, height: 200),
            CGRect(x: 3000, y: -5000, width: 1, height: 1),
        ]
        for rect in rects {
            let converter = Fixtures.converter
            XCTAssertEqual(converter.appKitRect(fromGlobal: converter.globalRect(fromAppKit: rect)), rect)
        }
    }

    func testPointConversion() {
        let c = Fixtures.converter
        XCTAssertEqual(c.globalPoint(fromAppKit: CGPoint(x: 10, y: 956)), CGPoint(x: 10, y: 0))
        XCTAssertEqual(c.globalPoint(fromAppKit: CGPoint(x: -100, y: 1307)), CGPoint(x: -100, y: -351))
        XCTAssertEqual(c.appKitPoint(fromGlobal: c.globalPoint(fromAppKit: CGPoint(x: -7, y: 3))), CGPoint(x: -7, y: 3))
    }

    func testNegativeHeightRectIsStandardized() {
        let flipped = CGRect(x: 0, y: 100, width: 50, height: -50)
        XCTAssertEqual(Fixtures.converter.globalRect(fromAppKit: flipped), CGRect(x: 0, y: 856, width: 50, height: 50))
    }

    func testPointsToPixels() {
        XCTAssertEqual(CoordinateConverter.pixels(fromPoints: CGSize(width: 735, height: 849), scale: 2), CGSize(width: 1470, height: 1698))
        XCTAssertEqual(CoordinateConverter.pixels(fromPoints: CGSize(width: 960, height: 1080), scale: 1), CGSize(width: 960, height: 1080))
    }
}
