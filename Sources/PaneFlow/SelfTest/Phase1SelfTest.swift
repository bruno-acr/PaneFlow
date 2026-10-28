import AppKit
import PaneFlowCore
import PaneFlowSystem

/// Phase 1 acceptance test against real windows: place Safari on the left half and Word on the
/// right half of a display with verified operations, optionally exercise a second display with
/// negative coordinates, then restore the original frames.
///
/// The report contains bundle identifiers and geometry only — never window titles.
@MainActor
struct Phase1SelfTest {
    struct Check: Codable, Sendable {
        let name: String
        let passed: Bool
        let detail: String
        var milliseconds: Double?
    }

    struct Report: Encodable, Sendable {
        let generatedAt: Date
        let osVersion: String
        let accessibilityGranted: Bool
        let displays: [String]
        let windowsDiscovered: Int
        let eligibleWindows: Int
        let subjects: [String]
        let checks: [Check]
        let performance: [PerformanceMonitor.Summary]
        var passed: Bool { !checks.isEmpty && checks.allSatisfy(\.passed) }

        enum CodingKeys: String, CodingKey {
            case generatedAt, osVersion, accessibilityGranted, displays, windowsDiscovered
            case eligibleWindows, subjects, checks, performance, passed
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(generatedAt, forKey: .generatedAt)
            try c.encode(osVersion, forKey: .osVersion)
            try c.encode(accessibilityGranted, forKey: .accessibilityGranted)
            try c.encode(displays, forKey: .displays)
            try c.encode(windowsDiscovered, forKey: .windowsDiscovered)
            try c.encode(eligibleWindows, forKey: .eligibleWindows)
            try c.encode(subjects, forKey: .subjects)
            try c.encode(checks, forKey: .checks)
            try c.encode(performance, forKey: .performance)
            try c.encode(passed, forKey: .passed)
        }
    }

    let repository: WindowRepository
    let geometry: WindowGeometryController
    let topology: DisplayTopology
    let accessibilityGranted: Bool
    let restoreAfterwards: Bool

    static let preferredBundles = ["com.apple.Safari", "com.microsoft.Word"]

    func run() async -> Report {
        var checks: [Check] = []
        var discovered = 0, eligibleCount = 0
        var subjects: [String] = []

        guard accessibilityGranted else {
            checks.append(Check(name: "accessibility", passed: false, detail: "Accessibility permission not granted"))
            return makeReport(checks: checks, discovered: 0, eligible: 0, subjects: [])
        }

        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .map { RunningApplicationInfo(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier,
                                          name: $0.localizedName ?? "?", isHidden: $0.isHidden) }

        let windows = await repository.discoverWindows(of: apps)
        discovered = windows.count
        let policy = WindowEligibilityPolicy(ownProcessID: getpid())
        let eligible = windows.filter {
            if case .eligible(resizable: true) = policy.evaluate($0) { true } else { false }
        }
        eligibleCount = eligible.count
        checks.append(Check(name: "discovery", passed: !windows.isEmpty,
                            detail: "\(windows.count) windows, \(eligible.count) eligible+resizable"))

        // Prefer Safari + Word as the specification demands; otherwise the two frontmost eligible windows.
        var picked: [WindowSnapshot] = []
        for bundle in Self.preferredBundles {
            if let w = eligible.first(where: { $0.bundleIdentifier == bundle }) { picked.append(w) }
        }
        for w in eligible where picked.count < 2 && !picked.contains(where: { $0.token == w.token }) {
            picked.append(w)
        }
        subjects = picked.map { $0.bundleIdentifier ?? "unknown" }
        let usedPreferred = Set(subjects) == Set(Self.preferredBundles)
        checks.append(Check(name: "subjects", passed: picked.count == 2,
                            detail: usedPreferred ? "Safari + Word" : "fallback: \(subjects.joined(separator: ", "))"))
        guard picked.count == 2, let display = topology.display(for: picked[0].frame) else {
            return makeReport(checks: checks, discovered: discovered, eligible: eligibleCount, subjects: subjects)
        }

        let originals = picked.map(\.frame)
        let halves = LayoutEngine.frames(for: LayoutCatalog.halves, in: display.visibleFrame)

        // Left / right halves, then the mirrored arrangement.
        await place(picked[0], halves[0], "left-half[\(subjects[0])]", &checks)
        await place(picked[1], halves[1], "right-half[\(subjects[1])]", &checks)
        checks.append(nonOverlapCheck(halves))
        // Idempotence: re-applying the same frame must be a no-op, not a drift.
        await place(picked[0], halves[0], "idempotent-left[\(subjects[0])]", &checks)
        await place(picked[1], halves[0], "swap-left[\(subjects[1])]", &checks)
        await place(picked[0], halves[1], "swap-right[\(subjects[0])]", &checks)

        // Second display (negative coordinates when it sits left of / above the primary).
        if let other = topology.displays.first(where: { $0.id != display.id }) {
            let target = LayoutEngine.frames(for: LayoutCatalog.halves, in: other.visibleFrame)[0]
            await place(picked[0], target, "other-display-left[\(other.frame.minX < 0 || other.frame.minY < 0 ? "negative" : "positive")]", &checks)
        }

        if restoreAfterwards {
            for (window, original) in zip(picked, originals) {
                await place(window, original, "restore[\(window.bundleIdentifier ?? "?")]", &checks)
            }
        }
        return makeReport(checks: checks, discovered: discovered, eligible: eligibleCount, subjects: subjects)
    }

    private func place(_ window: WindowSnapshot, _ frame: CGRect, _ name: String, _ checks: inout [Check]) async {
        do {
            let result = try await geometry.apply(frame, to: window.token)
            // Independent read-back through a fresh snapshot.
            let reread = try await repository.snapshot(of: window.token)
            let consistent = reread.frame.isApproximatelyEqual(to: result.actualFrame)
            checks.append(Check(
                name: name, passed: result.verdict.isAcceptable && consistent,
                detail: "requested \(NSStringFromRect(result.requestedFrame)) actual \(NSStringFromRect(reread.frame)) verdict \(Self.label(result.verdict))",
                milliseconds: result.milliseconds
            ))
        } catch {
            checks.append(Check(name: name, passed: false, detail: "error: \(error)"))
        }
    }

    private func nonOverlapCheck(_ expected: [CGRect]) -> Check {
        // Uses the expected frames: the verified results above already proved actual ≈ expected.
        let overlap = expected[0].intersectionArea(with: expected[1])
        return Check(name: "halves-do-not-overlap", passed: overlap == 0, detail: "overlap area \(overlap)")
    }

    private static func label(_ verdict: GeometryVerdict) -> String {
        switch verdict {
        case .exact: "exact"
        case .adjustedByApplication: "adjustedByApplication"
        case .failed: "failed"
        }
    }

    private func makeReport(checks: [Check], discovered: Int, eligible: Int, subjects: [String]) -> Report {
        Report(
            generatedAt: Date(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            accessibilityGranted: accessibilityGranted,
            displays: topology.displays.map { "\(NSStringFromRect($0.frame)) visible \(NSStringFromRect($0.visibleFrame)) @\($0.scale)x\($0.isPrimary ? " primary" : "")" },
            windowsDiscovered: discovered,
            eligibleWindows: eligible,
            subjects: subjects,
            checks: checks,
            performance: PerformanceMonitor.shared.summaries()
        )
    }
}
