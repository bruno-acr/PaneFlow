import CoreGraphics

/// Session-scoped handle for a window discovered through Accessibility.
///
/// Opaque and **never persisted**: it is only meaningful while the underlying `AXUIElement`
/// stays valid inside this PaneFlow process.
public struct WindowToken: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public var description: String { "w\(rawValue)" }
}

/// Point-in-time view of a window. Values may be stale as soon as they are read.
public struct WindowSnapshot: Sendable, Equatable, Identifiable {
    public let token: WindowToken
    public let pid: Int32
    public let bundleIdentifier: String?
    public let applicationName: String
    /// May contain sensitive information (document names). Never written to persistent logs.
    public let title: String?
    public let role: String?
    public let subrole: String?
    /// Global (CG/AX) coordinates.
    public let frame: CGRect
    public let isMinimized: Bool
    public let isMovable: Bool
    public let isResizable: Bool
    public let isMain: Bool
    public let isFocused: Bool
    /// Correlated `CGWindowID`, only when the match was unambiguous.
    public var windowID: UInt32?
    /// Front-to-back position among on-screen windows (0 = frontmost), when correlated.
    public var stackingOrder: Int?
    /// Matched (uniquely or ambiguously) to an on-screen window of the current Space.
    public var isOnScreen = false

    public var id: WindowToken { token }

    public init(
        token: WindowToken, pid: Int32, bundleIdentifier: String?, applicationName: String,
        title: String?, role: String?, subrole: String?, frame: CGRect,
        isMinimized: Bool, isMovable: Bool, isResizable: Bool, isMain: Bool, isFocused: Bool,
        windowID: UInt32? = nil, stackingOrder: Int? = nil
    ) {
        self.token = token
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.title = title
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.isMinimized = isMinimized
        self.isMovable = isMovable
        self.isResizable = isResizable
        self.isMain = isMain
        self.isFocused = isFocused
        self.windowID = windowID
        self.stackingOrder = stackingOrder
    }
}
