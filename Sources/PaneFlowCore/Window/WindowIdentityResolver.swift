import CoreGraphics

/// Signals about a window obtained from Accessibility.
public struct AccessibilityWindowSignal: Sendable, Equatable {
    public let token: WindowToken
    public let pid: Int32
    public let frame: CGRect
    public let title: String?

    public init(token: WindowToken, pid: Int32, frame: CGRect, title: String?) {
        self.token = token
        self.pid = pid
        self.frame = frame
        self.title = title
    }
}

/// Signals about a window obtained from the window server (`CGWindowListCopyWindowInfo`)
/// or ScreenCaptureKit (`SCWindow`, whose `windowID` is the same `CGWindowID`).
public struct ServerWindowSignal: Sendable, Equatable {
    public let windowID: UInt32
    public let pid: Int32
    public let frame: CGRect
    /// `nil` without Screen Recording permission.
    public let title: String?
    public let layer: Int
    /// Front-to-back index in the on-screen list.
    public let stackingOrder: Int

    public init(windowID: UInt32, pid: Int32, frame: CGRect, title: String?, layer: Int, stackingOrder: Int) {
        self.windowID = windowID
        self.pid = pid
        self.frame = frame
        self.title = title
        self.layer = layer
        self.stackingOrder = stackingOrder
    }
}

public enum WindowCorrelation: Sendable, Equatable {
    case unique(windowID: UInt32, stackingOrder: Int)
    /// More than one server window matches equally well; callers must not pick one
    /// (e.g. must not show a possibly wrong thumbnail).
    case ambiguous(windowIDs: [UInt32])
    case none
}

/// Correlates Accessibility windows with window-server windows without private API.
///
/// No single attribute is an identity (titles repeat, frames coincide, PIDs host many windows),
/// so a match requires: same PID, normal layer, frame equal within `frameTolerance`, and equal
/// titles whenever both sides expose one. Matches must also be one-to-one: if two AX windows
/// claim the same server window, both are reported as ambiguous.
public struct WindowIdentityResolver: Sendable {
    public var frameTolerance: CGFloat

    public init(frameTolerance: CGFloat = 2) {
        self.frameTolerance = frameTolerance
    }

    public func correlate(
        _ axWindows: [AccessibilityWindowSignal],
        with serverWindows: [ServerWindowSignal]
    ) -> [WindowToken: WindowCorrelation] {
        let normal = serverWindows.filter { $0.layer == 0 }
        var candidates: [WindowToken: [ServerWindowSignal]] = [:]

        for ax in axWindows {
            var matches = normal.filter {
                $0.pid == ax.pid && $0.frame.isApproximatelyEqual(to: ax.frame, tolerance: frameTolerance)
            }
            // A title only disqualifies when both sides expose one and they differ.
            if let axTitle = ax.title, !axTitle.isEmpty {
                matches.removeAll { $0.title != nil && $0.title != axTitle }
            }
            candidates[ax.token] = matches
        }

        // One-to-one: count how many AX windows uniquely claim each server window.
        var claims: [UInt32: Int] = [:]
        for matches in candidates.values where matches.count == 1 {
            claims[matches[0].windowID, default: 0] += 1
        }

        var result: [WindowToken: WindowCorrelation] = [:]
        for (token, matches) in candidates {
            switch matches.count {
            case 0:
                result[token] = WindowCorrelation.none
            case 1 where claims[matches[0].windowID] == 1:
                result[token] = .unique(windowID: matches[0].windowID, stackingOrder: matches[0].stackingOrder)
            default:
                result[token] = .ambiguous(windowIDs: matches.map(\.windowID).sorted())
            }
        }
        return result
    }
}
