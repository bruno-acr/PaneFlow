import CoreGraphics
@testable import PaneFlowCore

/// Display configurations used across tests. `realDevelopmentMac` was measured on the
/// development machine (MacBook + LG monitor to the left and slightly above).
enum Fixtures {
    // AppKit frames as reported by NSScreen.
    static let builtInAppKit = CGRect(x: 0, y: 0, width: 1470, height: 956)
    static let builtInVisibleAppKit = CGRect(x: 0, y: 74, width: 1470, height: 849)
    static let externalAppKit = CGRect(x: -1920, y: 227, width: 1920, height: 1080)

    static let converter = CoordinateConverter(primaryDisplayHeight: 956)

    static var realDevelopmentMac: DisplayTopology {
        DisplayTopology(displays: [
            DisplayDescriptor(
                id: 1, persistentID: "builtin", name: "Built-in Retina Display",
                frame: converter.globalRect(fromAppKit: builtInAppKit),
                visibleFrame: converter.globalRect(fromAppKit: builtInVisibleAppKit),
                scale: 2, isPrimary: true
            ),
            DisplayDescriptor(
                id: 2, persistentID: "lg", name: "LG FULL HD",
                frame: converter.globalRect(fromAppKit: externalAppKit),
                visibleFrame: converter.globalRect(fromAppKit: externalAppKit),
                scale: 1, isPrimary: false
            ),
        ])
    }

    /// Primary laptop with a 4K-ish monitor *above* it and another to the right.
    static var stacked: DisplayTopology {
        DisplayTopology(displays: [
            DisplayDescriptor(id: 10, persistentID: nil, name: "Primary", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                              visibleFrame: CGRect(x: 0, y: 38, width: 1512, height: 944), scale: 2, isPrimary: true),
            DisplayDescriptor(id: 11, persistentID: nil, name: "Above", frame: CGRect(x: -200, y: -1440, width: 2560, height: 1440),
                              visibleFrame: CGRect(x: -200, y: -1415, width: 2560, height: 1415), scale: 1, isPrimary: false),
            DisplayDescriptor(id: 12, persistentID: nil, name: "Right", frame: CGRect(x: 1512, y: 100, width: 1920, height: 1080),
                              visibleFrame: CGRect(x: 1512, y: 125, width: 1920, height: 1000), scale: 1, isPrimary: false),
        ])
    }
}
