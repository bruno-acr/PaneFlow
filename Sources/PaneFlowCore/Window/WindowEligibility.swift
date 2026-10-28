import CoreGraphics

/// Why a window cannot take part in a layout.
public enum IneligibilityReason: String, Sendable, Equatable, CaseIterable {
    case notAWindow
    case nonStandardSubrole
    case minimized
    case notMovable
    case tooSmall
    case ownedByPaneFlow
}

public enum Eligibility: Sendable, Equatable {
    /// `resizable == false` windows can still be positioned (e.g. centred) but not tiled to a size.
    case eligible(resizable: Bool)
    case ineligible(IneligibilityReason)

    public var isEligible: Bool {
        if case .eligible = self { true } else { false }
    }
}

/// Pure eligibility rules, shared by keyboard snapping, drag snapping and the Snap Assist picker.
public struct WindowEligibilityPolicy: Sendable {
    public var minimumSize: CGSize
    public var ownProcessID: Int32?

    /// Subroles of ordinary document/app windows. Dialogs, sheets, floating panels, system
    /// dialogs and popovers are excluded.
    public static let standardSubroles: Set<String> = ["AXStandardWindow"]

    public init(minimumSize: CGSize = CGSize(width: 60, height: 40), ownProcessID: Int32? = nil) {
        self.minimumSize = minimumSize
        self.ownProcessID = ownProcessID
    }

    public func evaluate(_ window: WindowSnapshot) -> Eligibility {
        if let ownProcessID, window.pid == ownProcessID { return .ineligible(.ownedByPaneFlow) }
        guard window.role == "AXWindow" else { return .ineligible(.notAWindow) }
        guard let subrole = window.subrole, Self.standardSubroles.contains(subrole) else {
            return .ineligible(.nonStandardSubrole)
        }
        if window.isMinimized { return .ineligible(.minimized) }
        if !window.isMovable { return .ineligible(.notMovable) }
        if window.frame.width < minimumSize.width || window.frame.height < minimumSize.height {
            return .ineligible(.tooSmall)
        }
        return .eligible(resizable: window.isResizable)
    }
}
