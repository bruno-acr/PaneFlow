import AppKit
import Carbon.HIToolbox

/// Global keyboard shortcuts through `RegisterEventHotKey` (public Carbon API; needs no
/// Input Monitoring permission). Handlers run on the main thread.
@MainActor
public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    public struct Shortcut: Hashable, Sendable {
        public let keyCode: UInt32
        /// Carbon modifier mask (`controlKey | optionKey`, …).
        public let modifiers: UInt32
        public let display: String

        public init(keyCode: Int, modifiers: Int, display: String) {
            self.keyCode = UInt32(keyCode)
            self.modifiers = UInt32(modifiers)
            self.display = display
        }
    }

    public enum RegistrationError: Error, Equatable {
        /// Another app already owns this combination.
        case conflict
        case failed(OSStatus)
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    private init() {}

    /// Registers `shortcut`; returns its id for `unregisterAll`.
    @discardableResult
    public func register(_ shortcut: Shortcut, handler: @escaping () -> Void) throws(RegistrationError) -> UInt32 {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x506E_466C) /* 'PnFl' */, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &reference)
        guard status == noErr, let reference else {
            throw status == OSStatus(eventHotKeyExistsErr) ? .conflict : .failed(status)
        }
        handlers[id] = handler
        references[id] = reference
        return id
    }

    public func unregisterAll() {
        references.values.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            MainActor.assumeIsolated { HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
