import Foundation

/// Read-only view of macOS window-manager preferences that interfere with PaneFlow.
///
/// The `com.apple.WindowManager` keys are undocumented, so every value is a *heuristic*:
/// `nil` means "unknown" and callers must not assume either state. PaneFlow never writes them.
public struct NativeWindowManagerSettings: Sendable, Equatable, Codable {
    /// macOS 15+: "Drag windows to screen edges to tile". Competes with PaneFlow's edge snapping.
    public let edgeDragTilingEnabled: Bool?
    /// macOS 15+: "Drag windows to menu bar to fill screen".
    public let topEdgeTilingEnabled: Bool?
    public let stageManagerEnabled: Bool?

    public static func read() -> NativeWindowManagerSettings {
        let defaults = UserDefaults(suiteName: "com.apple.WindowManager")
        func flag(_ key: String) -> Bool? {
            (defaults?.object(forKey: key) as? NSNumber)?.boolValue
        }
        let tilingAvailable = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
        return NativeWindowManagerSettings(
            // Tiling defaults to on in macOS 15+ when the key is absent.
            edgeDragTilingEnabled: tilingAvailable ? (flag("EnableTilingByEdgeDrag") ?? true) : false,
            topEdgeTilingEnabled: tilingAvailable ? (flag("EnableTopTilingByEdgeDrag") ?? true) : false,
            stageManagerEnabled: flag("GloballyEnabled")
        )
    }
}
