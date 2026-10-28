import ApplicationServices
import CoreGraphics

/// Errors surfaced by Accessibility calls, mapped from `AXError`.
public enum AXFailure: Error, Sendable, Equatable {
    /// The element no longer exists (window closed, app quit).
    case invalidElement
    /// The target app did not answer within the messaging timeout or refused the request.
    case cannotComplete
    case attributeUnsupported(String)
    case notSettable(String)
    case notTrusted
    case processTerminated
    case unexpectedValue(String)
    case other(Int32)

    init(_ error: AXError, attribute: String = "") {
        switch error {
        case .invalidUIElement, .invalidUIElementObserver: self = .invalidElement
        case .cannotComplete: self = .cannotComplete
        case .attributeUnsupported, .noValue: self = .attributeUnsupported(attribute)
        case .apiDisabled: self = .notTrusted
        default: self = .other(error.rawValue)
        }
    }
}

/// Typed wrapper over `AXUIElement`.
///
/// `@unchecked Sendable`: `AXUIElement` is an immutable CF reference whose functions may be called
/// from any thread. PaneFlow only dereferences it inside `AccessibilityExecutor`, never on the main
/// thread, so a slow target app can never stall the UI.
public struct AXElement: @unchecked Sendable, Hashable {
    public let raw: AXUIElement

    public init(_ raw: AXUIElement) { self.raw = raw }

    public static func application(pid: pid_t) -> AXElement {
        AXElement(AXUIElementCreateApplication(pid))
    }

    public static let systemWide = AXElement(AXUIElementCreateSystemWide())

    public static func == (lhs: AXElement, rhs: AXElement) -> Bool { CFEqual(lhs.raw, rhs.raw) }
    public func hash(into hasher: inout Hasher) { hasher.combine(CFHash(raw)) }

    public var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(raw, &pid) == .success ? pid : nil
    }

    // MARK: Reading

    public func copyValue(_ attribute: String) throws(AXFailure) -> CFTypeRef {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(raw, attribute as CFString, &value)
        guard error == .success else { throw AXFailure(error, attribute: attribute) }
        guard let value else { throw .attributeUnsupported(attribute) }
        return value
    }

    public func string(_ attribute: String) -> String? {
        (try? copyValue(attribute)) as? String
    }

    public func bool(_ attribute: String) -> Bool? {
        guard let value = try? copyValue(attribute), CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    public func element(_ attribute: String) -> AXElement? {
        guard let value = try? copyValue(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXElement(value as! AXUIElement)
    }

    public func elements(_ attribute: String) throws(AXFailure) -> [AXElement] {
        let value = try copyValue(attribute)
        guard let array = value as? [AnyObject] else { throw .unexpectedValue(attribute) }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? AXElement(item as! AXUIElement) : nil
        }
    }

    public func point(_ attribute: String) throws(AXFailure) -> CGPoint {
        var point = CGPoint.zero
        guard AXValueGetValue(try axValue(attribute, type: .cgPoint), .cgPoint, &point) else {
            throw .unexpectedValue(attribute)
        }
        return point
    }

    public func size(_ attribute: String) throws(AXFailure) -> CGSize {
        var size = CGSize.zero
        guard AXValueGetValue(try axValue(attribute, type: .cgSize), .cgSize, &size) else {
            throw .unexpectedValue(attribute)
        }
        return size
    }

    private func axValue(_ attribute: String, type: AXValueType) throws(AXFailure) -> AXValue {
        let value = try copyValue(attribute)
        guard CFGetTypeID(value) == AXValueGetTypeID() else { throw .unexpectedValue(attribute) }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == type else { throw .unexpectedValue(attribute) }
        return axValue
    }

    /// Reads several attributes in one IPC round trip. Missing or failed attributes are omitted.
    public func values(_ attributes: [String]) throws(AXFailure) -> [String: CFTypeRef] {
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(raw, attributes as CFArray, AXCopyMultipleAttributeOptions(), &values)
        guard error == .success, let array = values as? [AnyObject] else { throw AXFailure(error) }
        var result: [String: CFTypeRef] = [:]
        for (attribute, value) in zip(attributes, array) {
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError {
                continue
            }
            result[attribute] = value
        }
        return result
    }

    /// Global (AX) frame from position + size.
    public func frame() throws(AXFailure) -> CGRect {
        let origin = try point(kAXPositionAttribute)
        let size = try size(kAXSizeAttribute)
        return CGRect(origin: origin, size: size)
    }

    public func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(raw, attribute as CFString, &settable) == .success && settable.boolValue
    }

    // MARK: Writing

    public func setPosition(_ point: CGPoint) throws(AXFailure) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { throw .unexpectedValue(kAXPositionAttribute) }
        try set(kAXPositionAttribute, value)
    }

    public func setSize(_ size: CGSize) throws(AXFailure) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { throw .unexpectedValue(kAXSizeAttribute) }
        try set(kAXSizeAttribute, value)
    }

    public func set(_ attribute: String, _ value: CFTypeRef) throws(AXFailure) {
        let error = AXUIElementSetAttributeValue(raw, attribute as CFString, value)
        guard error == .success else { throw AXFailure(error, attribute: attribute) }
    }

    public func perform(_ action: String) throws(AXFailure) {
        let error = AXUIElementPerformAction(raw, action as CFString)
        guard error == .success else { throw AXFailure(error, attribute: action) }
    }

    public func setMessagingTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(raw, seconds)
    }

    /// Element under a global point, as seen by the system-wide element.
    public static func element(at point: CGPoint) -> AXElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide.raw, Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }
        return AXElement(element)
    }
}
