import CoreGraphics
import Foundation
import ScreenCaptureKit

/// One-shot window thumbnails through ScreenCaptureKit.
///
/// - Captures only on demand (Snap Assist open), never continuously; nothing is written to disk.
/// - Images are downscaled by the capture itself (`maxPixelSize`), so no full-size bitmap is kept.
/// - At most `maxConcurrent` captures run at once; cancelling the calling task stops the rest.
/// - Requires Screen Recording; without it callers fall back to icons and titles.
public final class WindowThumbnailService: Sendable {
    public static let shared = WindowThumbnailService()

    public let maxConcurrent: Int

    public init(maxConcurrent: Int = 4) {
        self.maxConcurrent = maxConcurrent
    }

    public static var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    /// Captures thumbnails for `windowIDs` (in priority order) and reports each as soon as it is ready.
    public func capture(
        windowIDs: [UInt32], maxPixelSize: Int = 480,
        onImage: @escaping @MainActor @Sendable (UInt32, CGImage) -> Void
    ) async {
        guard Self.isAuthorized, !windowIDs.isEmpty else { return }
        let clock = ContinuousClock(), start = clock.now
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            Log.capture.error("Shareable content unavailable: \(error.localizedDescription, privacy: .public)")
            return
        }
        let byID = Dictionary(content.windows.map { ($0.windowID, UncheckedWindow(window: $0)) }, uniquingKeysWith: { a, _ in a })
        let jobs = windowIDs.compactMap { id in byID[id].map { (id, $0) } }

        await withTaskGroup(of: Void.self) { group in
            var iterator = jobs.makeIterator()
            func addNext() -> Bool {
                guard let (id, window) = iterator.next() else { return false }
                group.addTask {
                    guard !Task.isCancelled, let image = await Self.captureOne(window, maxPixelSize: maxPixelSize) else { return }
                    await onImage(id, image)
                }
                return true
            }
            for _ in 0..<maxConcurrent where addNext() {}
            while await group.next() != nil {
                if Task.isCancelled { group.cancelAll(); break }
                _ = addNext()
            }
        }
        PerformanceMonitor.shared.record("capture.batch", milliseconds: (clock.now - start).milliseconds)
    }

    private static func captureOne(_ wrapped: UncheckedWindow, maxPixelSize: Int) async -> CGImage? {
        let window = wrapped.window
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        let size = CGSize(width: window.frame.width * scale, height: window.frame.height * scale)
        let factor = min(1, CGFloat(maxPixelSize) / max(size.width, size.height, 1))
        config.width = max(1, Int(size.width * factor))
        config.height = max(1, Int(size.height * factor))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            Log.capture.debug("Capture failed for a window: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// `SCWindow` is an immutable description object; it is only read inside capture tasks.
private struct UncheckedWindow: @unchecked Sendable {
    let window: SCWindow
}
