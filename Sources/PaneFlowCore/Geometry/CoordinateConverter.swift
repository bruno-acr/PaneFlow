import CoreGraphics

/// Converts between the coordinate spaces used on macOS.
///
/// PaneFlow's canonical space is the **global** space shared by CoreGraphics and the
/// Accessibility API: origin at the top-left of the primary display, Y growing downwards,
/// in points. AppKit uses the bottom-left of the primary display with Y growing upwards.
///
/// The conversion only depends on the height of the primary display (the one whose AppKit
/// frame has origin `(0, 0)`). Secondary displays may have negative coordinates in both spaces.
public struct CoordinateConverter: Sendable, Equatable {
    public let primaryDisplayHeight: CGFloat

    public init(primaryDisplayHeight: CGFloat) {
        self.primaryDisplayHeight = primaryDisplayHeight
    }

    /// AppKit rect → global (CG/AX) rect. The transform is its own inverse.
    public func globalRect(fromAppKit rect: CGRect) -> CGRect {
        let r = rect.standardized
        return CGRect(x: r.minX, y: primaryDisplayHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Global (CG/AX) rect → AppKit rect.
    public func appKitRect(fromGlobal rect: CGRect) -> CGRect {
        globalRect(fromAppKit: rect)
    }

    public func globalPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryDisplayHeight - point.y)
    }

    public func appKitPoint(fromGlobal point: CGPoint) -> CGPoint {
        globalPoint(fromAppKit: point)
    }

    /// Points → pixels for a display with the given backing scale factor.
    public static func pixels(fromPoints size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}
