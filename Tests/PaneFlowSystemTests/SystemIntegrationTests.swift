import AppKit
import ApplicationServices
import XCTest
@testable import PaneFlowCore
@testable import PaneFlowSystem

/// Integration tests against the real window server and displays.
/// Tests that need Accessibility are skipped (not passed) when the test runner is not trusted.
final class SystemIntegrationTests: XCTestCase {
    @MainActor
    func testDisplayManagerMatchesCoreGraphics() {
        let manager = DisplayManager()
        let topology = manager.topology
        XCTAssertFalse(topology.displays.isEmpty)
        XCTAssertEqual(topology.displays.filter(\.isPrimary).count, 1)
        for display in topology.displays {
            // Global frame computed from NSScreen must equal CoreGraphics' own bounds.
            XCTAssertEqual(display.frame, CGDisplayBounds(display.id), "display \(display.id)")
            XCTAssertTrue(display.frame.contains(display.visibleFrame), "visible frame inside frame")
            XCTAssertGreaterThan(display.scale, 0)
        }
    }

    func testServerWindowListIsFrontToBackAndWellFormed() {
        let windows = WindowRepository.onScreenServerWindows()
        XCTAssertEqual(windows.map(\.stackingOrder), Array(windows.indices))
        XCTAssertEqual(Set(windows.map(\.windowID)).count, windows.count, "window ids are unique")
    }

    func testNativeSettingsReadDoesNotCrash() {
        let settings = NativeWindowManagerSettings.read()
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)) {
            XCTAssertNotNil(settings.edgeDragTilingEnabled)
        }
    }

    func testAXFailureMapping() {
        XCTAssertEqual(AXFailure(.invalidUIElement), .invalidElement)
        XCTAssertEqual(AXFailure(.cannotComplete), .cannotComplete)
        XCTAssertEqual(AXFailure(.apiDisabled), .notTrusted)
        XCTAssertEqual(AXFailure(.noValue, attribute: "AXTitle"), .attributeUnsupported("AXTitle"))
    }

    func testProcessLivenessProbe() {
        XCTAssertTrue(WindowGeometryController.processIsAlive(getpid()))
        XCTAssertFalse(WindowGeometryController.processIsAlive(99_999_999))
    }

    func testRestoreManagerKeepsFirstOriginal() {
        let manager = WindowRestoreManager(capacity: 2)
        let a = WindowToken(rawValue: 1), b = WindowToken(rawValue: 2), c = WindowToken(rawValue: 3)
        manager.recordOriginal(CGRect(x: 1, y: 1, width: 1, height: 1), for: a)
        manager.recordOriginal(CGRect(x: 9, y: 9, width: 9, height: 9), for: a)
        XCTAssertEqual(manager.original(for: a), CGRect(x: 1, y: 1, width: 1, height: 1))
        manager.recordOriginal(.zero, for: b)
        manager.recordOriginal(.zero, for: c)
        XCTAssertNil(manager.original(for: a), "oldest entry evicted at capacity")
        manager.clear(b)
        XCTAssertNil(manager.original(for: b))
    }

    func testUnknownTokenFailsCleanly() async {
        let repository = WindowRepository()
        let controller = WindowGeometryController(repository: repository)
        do {
            _ = try await controller.apply(CGRect(x: 0, y: 0, width: 100, height: 100), to: WindowToken(rawValue: 12345))
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error, .windowGone)
        }
    }

    func testDiscoveryRequiresAccessibility() async throws {
        try XCTSkipUnless(AXIsProcessTrusted(), "Accessibility not granted to the test runner")
        let apps = await MainActor.run {
            NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map {
                RunningApplicationInfo(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier,
                                       name: $0.localizedName ?? "?", isHidden: $0.isHidden)
            }
        }
        let windows = await WindowRepository().discoverWindows(of: apps)
        XCTAssertFalse(windows.isEmpty)
    }
}
