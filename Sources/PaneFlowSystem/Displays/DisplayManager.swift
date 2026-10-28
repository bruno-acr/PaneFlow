import AppKit
import CoreGraphics
import Observation
import PaneFlowCore

/// Publishes the current `DisplayTopology` and rebuilds it when displays change.
/// Event-driven (`didChangeScreenParametersNotification`), no polling.
@MainActor
@Observable
public final class DisplayManager {
    public private(set) var topology: DisplayTopology
    public private(set) var converter: CoordinateConverter
    /// Bumped on every rebuild so consumers can discard geometry computed for an old topology.
    public private(set) var generation = 0

    @ObservationIgnored public var onChange: ((DisplayTopology) -> Void)?
    @ObservationIgnored private var observer: NSObjectProtocol?

    public init() {
        (topology, converter) = Self.build()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    public func rebuild() {
        let (newTopology, newConverter) = Self.build()
        guard newTopology != topology else { return }
        topology = newTopology
        converter = newConverter
        generation += 1
        Log.displays.info("Display configuration changed: \(newTopology.displays.count) display(s), generation \(self.generation)")
        onChange?(newTopology)
    }

    private static func build() -> (DisplayTopology, CoordinateConverter) {
        let screens = NSScreen.screens
        // The primary display is the one whose AppKit frame starts at the origin; CGMainDisplayID agrees.
        let primaryHeight = screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? CGDisplayBounds(CGMainDisplayID()).height
        let converter = CoordinateConverter(primaryDisplayHeight: primaryHeight)
        let displays = screens.map { screen -> DisplayDescriptor in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
            return DisplayDescriptor(
                id: id,
                persistentID: uuid.flatMap { CFUUIDCreateString(nil, $0) as String? },
                name: screen.localizedName,
                frame: converter.globalRect(fromAppKit: screen.frame),
                visibleFrame: converter.globalRect(fromAppKit: screen.visibleFrame),
                scale: screen.backingScaleFactor,
                isPrimary: screen.frame.origin == .zero
            )
        }
        return (DisplayTopology(displays: displays), converter)
    }
}
