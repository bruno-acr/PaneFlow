import AppKit
import ApplicationServices
import CoreGraphics
import Observation

public enum PermissionKind: String, Sendable, CaseIterable, Codable {
    case accessibility
    case screenRecording
}

/// Tracks the permissions PaneFlow depends on and detects grants/revocations.
///
/// Change detection: re-check when PaneFlow becomes active, on the (undocumented but public-channel)
/// `com.apple.accessibility.api` distributed notification, and on a low-frequency timer
/// (30 s, 10 s tolerance). The timer only calls two cheap in-process functions; it is the only
/// reliable signal for revocations made while PaneFlow is in the background. While onboarding is
/// visible the interval drops to 1 s so the UI reacts immediately.
@MainActor
@Observable
public final class PermissionManager {
    public private(set) var accessibilityGranted: Bool
    public private(set) var screenRecordingGranted: Bool

    @ObservationIgnored public var onChange: ((PermissionKind, Bool) -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var interactive = false

    public init() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The trust database is updated slightly after the notification is posted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.refresh() }
            }
        })
        scheduleTimer()
    }

    /// Faster re-checks while the permissions window is on screen.
    public func setInteractiveMonitoring(_ enabled: Bool) {
        interactive = enabled
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval: TimeInterval = interactive ? 1 : 30
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = interactive ? 0.2 : 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func refresh() {
        let ax = AXIsProcessTrusted()
        if ax != accessibilityGranted {
            accessibilityGranted = ax
            Log.permissions.notice("Accessibility permission \(ax ? "granted" : "revoked", privacy: .public)")
            onChange?(.accessibility, ax)
        }
        let sr = CGPreflightScreenCaptureAccess()
        if sr != screenRecordingGranted {
            screenRecordingGranted = sr
            Log.permissions.notice("Screen Recording permission \(sr ? "granted" : "revoked", privacy: .public)")
            onChange?(.screenRecording, sr)
        }
    }

    public func isGranted(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility: accessibilityGranted
        case .screenRecording: screenRecordingGranted
        }
    }

    /// Shows the system prompt (adds PaneFlow to the list) and opens the relevant Settings pane.
    public func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        refresh()
    }

    public func openSystemSettings(for kind: PermissionKind) {
        let anchor = switch kind {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
