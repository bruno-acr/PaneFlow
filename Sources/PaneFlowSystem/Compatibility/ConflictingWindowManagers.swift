import AppKit

/// Other window managers that also snap dragged windows or claim the same shortcuts. Two snapping
/// engines on the same gesture fight over the window, so the user is told when one is running.
public enum ConflictingWindowManagers {
    public static let known: [String: String] = [
        "com.knollsoft.Rectangle": "Rectangle",
        "com.knollsoft.Hookshot": "Hookshot",
        "com.crowdcafe.windowmagnet": "Magnet",
        "com.hegenberg.BetterSnapTool": "BetterSnapTool",
        "com.hegenberg.BetterTouchTool": "BetterTouchTool",
        "com.manytricks.Moom": "Moom",
        "com.sergey-gerasimenko.Divvy": "Divvy",
        "com.mizage.Divvy": "Divvy",
        "com.amethyst.Amethyst": "Amethyst",
        "com.koekeishiya.yabai": "yabai",
        "com.lwouis.alt-tab-macos": "AltTab",
    ]

    /// Names of running apps known to snap windows (AltTab only overlaps on shortcuts, so it is excluded).
    @MainActor
    public static func running() -> [String] {
        let names = NSWorkspace.shared.runningApplications.compactMap { app in
            app.bundleIdentifier.flatMap { known[$0] }
        }
        return Array(Set(names)).filter { $0 != "AltTab" }.sorted()
    }
}
