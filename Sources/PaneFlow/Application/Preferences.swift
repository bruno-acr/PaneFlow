import Foundation

/// User preferences (UserDefaults). Phase 8 replaces this with the full SettingsStore + Settings window.
@MainActor
struct Preferences {
    private let defaults = UserDefaults.standard

    private func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    var enabled: Bool {
        get { bool("enabled", default: true) }
        nonmutating set { defaults.set(newValue, forKey: "enabled") }
    }

    /// Snap when a window is dragged to a screen edge.
    var snapOnDrag: Bool {
        get { bool("snapOnDrag", default: true) }
        nonmutating set { defaults.set(newValue, forKey: "snapOnDrag") }
    }

    /// Resize adjacent windows together when their shared edge is dragged.
    var linkedResize: Bool {
        get { bool("linkedResize", default: true) }
        nonmutating set { defaults.set(newValue, forKey: "linkedResize") }
    }

    /// After snapping, offer the empty area with a picker of other windows.
    var snapAssist: Bool {
        get { bool("snapAssist", default: true) }
        nonmutating set { defaults.set(newValue, forKey: "snapAssist") }
    }

    /// Hold the cursor briefly at edges shared between displays while dragging a window.
    var edgeResistance: Bool {
        get { bool("edgeResistance", default: true) }
        nonmutating set { defaults.set(newValue, forKey: "edgeResistance") }
    }

    var keyboardShortcuts: Bool {
        get { bool("keyboardShortcuts", default: true) }
        nonmutating set { defaults.set(newValue, forKey: "keyboardShortcuts") }
    }
}
