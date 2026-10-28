import ApplicationServices
import CoreGraphics
import Foundation
import PaneFlowCore

/// Minimal, `Sendable` description of a running GUI application, captured on the main thread.
public struct RunningApplicationInfo: Sendable, Equatable {
    public let pid: pid_t
    public let bundleIdentifier: String?
    public let name: String
    public let isHidden: Bool

    public init(pid: pid_t, bundleIdentifier: String?, name: String, isHidden: Bool) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.isHidden = isHidden
    }
}

/// Discovers windows through Accessibility and correlates them with the window server.
///
/// Holds the session-scoped mapping `WindowToken ↔ AXUIElement`. Tokens are stable for as long as
/// the element is valid; they are never persisted.
public final class WindowRepository: @unchecked Sendable {
    private let executor: AccessibilityExecutor
    private let resolver = WindowIdentityResolver()
    // Guarded by `lock`. Mutated only on the executor queue, read from anywhere.
    private let lock = NSLock()
    private var tokensByElement: [AXElement: WindowToken] = [:]
    private var elementsByToken: [WindowToken: AXElement] = [:]
    private var appsByToken: [WindowToken: RunningApplicationInfo] = [:]
    private var nextToken: UInt64 = 1

    private static let snapshotAttributes = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXPositionAttribute,
        kAXSizeAttribute, kAXMinimizedAttribute, kAXMainAttribute, kAXFocusedAttribute,
    ] as [String]

    public init(executor: AccessibilityExecutor = .shared) {
        self.executor = executor
    }

    // MARK: Token registry

    public func element(for token: WindowToken) -> AXElement? {
        lock.withLock { elementsByToken[token] }
    }

    public func application(for token: WindowToken) -> RunningApplicationInfo? {
        lock.withLock { appsByToken[token] }
    }

    private func token(for element: AXElement, app: RunningApplicationInfo) -> WindowToken {
        lock.withLock {
            if let existing = tokensByElement[element] { return existing }
            let token = WindowToken(rawValue: nextToken)
            nextToken += 1
            tokensByElement[element] = token
            elementsByToken[token] = element
            appsByToken[token] = app
            return token
        }
    }

    /// Drops a token whose element became invalid.
    public func forget(_ token: WindowToken) {
        lock.withLock {
            if let element = elementsByToken.removeValue(forKey: token) {
                tokensByElement.removeValue(forKey: element)
            }
            appsByToken.removeValue(forKey: token)
        }
    }

    private func forgetAll(pid: pid_t, except keep: Set<WindowToken>) {
        let stale = lock.withLock { appsByToken.filter { $0.value.pid == pid && !keep.contains($0.key) }.map(\.key) }
        stale.forEach(forget)
    }

    // MARK: Discovery

    /// Enumerates the windows of `apps`, correlates them with on-screen server windows and returns
    /// them ordered front-to-back (correlated windows first, then by application order).
    public func discoverWindows(of apps: [RunningApplicationInfo]) async -> [WindowSnapshot] {
        await executor.perform { [self] in
            let clock = ContinuousClock()
            let start = clock.now
            var snapshots: [WindowSnapshot] = []
            var failedApps = 0
            for app in apps where !app.isHidden {
                do throws(AXFailure) {
                    let appElement = AXElement.application(pid: app.pid)
                    let windows = try appElement.elements(kAXWindowsAttribute)
                    var seen = Set<WindowToken>()
                    for window in windows {
                        if let snapshot = try? readSnapshot(window, app: app) {
                            snapshots.append(snapshot)
                            seen.insert(snapshot.token)
                        }
                    }
                    forgetAll(pid: app.pid, except: seen)
                } catch {
                    // Apps without windows report attributeUnsupported/noValue; unresponsive ones cannotComplete.
                    if error == .cannotComplete { failedApps += 1 }
                }
            }
            let correlated = correlate(snapshots)
            let elapsed = (clock.now - start).milliseconds
            PerformanceMonitor.shared.record("window.discovery", milliseconds: elapsed)
            Log.discovery.debug("Discovered \(correlated.count) windows in \(apps.count) apps (\(failedApps) unresponsive) in \(elapsed, format: .fixed(precision: 1)) ms")
            return correlated
        }
    }

    /// Fresh snapshot of a known window.
    public func snapshot(of token: WindowToken) async throws -> WindowSnapshot {
        guard let element = element(for: token), let app = application(for: token) else { throw AXFailure.invalidElement }
        return try await executor.run { [self] in
            do throws(AXFailure) {
                return try readSnapshot(element, app: app)
            } catch {
                if error == .invalidElement { forget(token) }
                throw error
            }
        }
    }

    /// Resolves a window-server window to its Accessibility window: same PID and, among that app's
    /// windows, the one whose frame matches. Returns nil when absent or ambiguous.
    ///
    /// The server frame may be a few milliseconds old (captured at mouse-down) while the user is
    /// already dragging, so an exact match is preferred but a *unique* close match is accepted:
    /// edges within `drift` points. Two close candidates are ambiguous and resolve to nil.
    public func resolve(_ server: ServerWindowSignal, app: RunningApplicationInfo, drift: CGFloat = 60) async -> WindowSnapshot? {
        await executor.perform { [self] in
            guard let windows = try? AXElement.application(pid: app.pid).elements(kAXWindowsAttribute) else { return nil }
            let framed = windows.compactMap { element in (try? element.frame()).map { (element, $0) } }
            func distance(_ r: CGRect) -> CGFloat {
                max(abs(r.minX - server.frame.minX), abs(r.minY - server.frame.minY),
                    abs(r.maxX - server.frame.maxX), abs(r.maxY - server.frame.maxY))
            }
            let exact = framed.filter { distance($0.1) <= 2 }
            let close = exact.isEmpty ? framed.filter { distance($0.1) <= drift } : exact
            guard close.count == 1, var snapshot = try? readSnapshot(close[0].0, app: app) else { return nil }
            snapshot.windowID = server.windowID
            snapshot.stackingOrder = server.stackingOrder
            return snapshot
        }
    }

    /// Current frames of several windows in one executor hop. Missing entries are windows that vanished.
    public func frames(of tokens: [WindowToken]) async -> [WindowToken: CGRect] {
        let elements = tokens.compactMap { token in element(for: token).map { (token, $0) } }
        return await executor.perform {
            var result: [WindowToken: CGRect] = [:]
            for (token, element) in elements {
                if let frame = try? element.frame() { result[token] = frame }
            }
            return result
        }
    }

    /// Focused window of the given (normally frontmost) application.
    public func focusedWindow(of app: RunningApplicationInfo) async throws -> WindowSnapshot {
        try await executor.run { [self] in
            let appElement = AXElement.application(pid: app.pid)
            guard let window = appElement.element(kAXFocusedWindowAttribute) ?? appElement.element(kAXMainWindowAttribute) else {
                throw AXFailure.attributeUnsupported(kAXFocusedWindowAttribute)
            }
            return try readSnapshot(window, app: app)
        }
    }

    // MARK: Executor-queue helpers

    private func readSnapshot(_ element: AXElement, app: RunningApplicationInfo) throws(AXFailure) -> WindowSnapshot {
        let values = try element.values(Self.snapshotAttributes)
        guard let positionValue = values[kAXPositionAttribute], let sizeValue = values[kAXSizeAttribute] else {
            throw .attributeUnsupported(kAXPositionAttribute)
        }
        var origin = CGPoint.zero, size = CGSize.zero
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { throw .unexpectedValue(kAXPositionAttribute) }

        func flag(_ attribute: String) -> Bool {
            guard let v = values[attribute], CFGetTypeID(v) == CFBooleanGetTypeID() else { return false }
            return CFBooleanGetValue((v as! CFBoolean))
        }

        return WindowSnapshot(
            token: token(for: element, app: app),
            pid: app.pid,
            bundleIdentifier: app.bundleIdentifier,
            applicationName: app.name,
            title: values[kAXTitleAttribute] as? String,
            role: values[kAXRoleAttribute] as? String,
            subrole: values[kAXSubroleAttribute] as? String,
            frame: CGRect(origin: origin, size: size),
            isMinimized: flag(kAXMinimizedAttribute),
            isMovable: element.isSettable(kAXPositionAttribute),
            isResizable: element.isSettable(kAXSizeAttribute),
            isMain: flag(kAXMainAttribute),
            isFocused: flag(kAXFocusedAttribute)
        )
    }

    private func correlate(_ snapshots: [WindowSnapshot]) -> [WindowSnapshot] {
        let server = Self.onScreenServerWindows()
        let signals = snapshots.map {
            AccessibilityWindowSignal(token: $0.token, pid: $0.pid, frame: $0.frame, title: $0.title)
        }
        let correlations = resolver.correlate(signals, with: server)
        let enriched = snapshots.map { snapshot -> WindowSnapshot in
            var s = snapshot
            switch correlations[snapshot.token] {
            case let .unique(windowID, order):
                s.windowID = windowID
                s.stackingOrder = order
                s.isOnScreen = true
            case let .ambiguous(ids):
                // On screen, but no thumbnail: we cannot tell which server window it is.
                s.isOnScreen = true
                s.stackingOrder = server.first { ids.contains($0.windowID) }?.stackingOrder
            default:
                break
            }
            return s
        }
        // Stable sort: on-screen windows front-to-back, then everything else in discovery order.
        return enriched.enumerated().sorted { a, b in
            switch (a.element.stackingOrder, b.element.stackingOrder) {
            case let (x?, y?): x < y
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Current bounds of specific windows straight from the window server (no IPC to the owning app).
    /// Authoritative during title-bar drags, which the window server performs itself while the
    /// app's Accessibility position lags behind.
    public static func serverFrames(of ids: [UInt32]) -> [UInt32: CGRect] {
        guard !ids.isEmpty else { return [:] }
        let array = ids.map { NSNumber(value: $0) } as CFArray
        guard let list = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] else { return [:] }
        var result: [UInt32: CGRect] = [:]
        for info in list {
            guard let number = info[kCGWindowNumber as String] as? UInt32,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            result[number] = bounds
        }
        return result
    }

    /// On-screen windows of the current Space, front-to-back. Titles are nil without Screen Recording.
    public static func onScreenServerWindows() -> [ServerWindowSignal] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return list.enumerated().compactMap { index, info in
            guard let number = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            return ServerWindowSignal(
                windowID: number, pid: pid, frame: bounds,
                title: info[kCGWindowName as String] as? String,
                layer: info[kCGWindowLayer as String] as? Int ?? 0,
                stackingOrder: index
            )
        }
    }
}

extension Duration {
    public var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }
}
