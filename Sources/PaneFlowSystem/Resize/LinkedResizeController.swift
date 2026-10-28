import AppKit
import PaneFlowCore

/// Keeps adjacent windows together while the user drags the edge between them.
///
/// Live updates use the unverified fast path at most once per completed write (coalesced to the
/// latest driver frame). When the mouse is released the followers get a verified write and, if one
/// refused to shrink, the driver is pulled back to its edge so the windows never overlap.
@MainActor
public final class LinkedResizeController {
    private let repository: WindowRepository
    private let geometry: WindowGeometryController
    private let topologyProvider: () -> DisplayTopology
    private let policy = WindowEligibilityPolicy(ownProcessID: getpid())

    private var session: SnapSessionID?
    private var driver: WindowSnapshot?
    private var original: CGRect = .zero
    private var plans: [LinkedResize.Edge: LinkedResize.Plan] = [:]
    private var planningDone = false
    private var latest: CGRect?
    private var writeInFlight = false

    public init(repository: WindowRepository, geometry: WindowGeometryController, topology: @escaping () -> DisplayTopology) {
        self.repository = repository
        self.geometry = geometry
        topologyProvider = topology
    }

    public func begin(session: SnapSessionID, driver: WindowSnapshot, original: CGRect, serverWindows: [ServerWindowSignal]) {
        self.session = session
        self.driver = driver
        self.original = original
        plans = [:]
        planningDone = false
        latest = nil
        writeInFlight = false

        let topology = topologyProvider()
        let display = topology.display(for: original)
        // Cheap prefilter on window-server data before any Accessibility work.
        let near = serverWindows.filter { server in
            server.windowID != driver.windowID
                && !(server.pid == driver.pid && server.frame.isApproximatelyEqual(to: original, tolerance: 2))
                && server.frame.intersects(original.insetBy(dx: -24, dy: -24))
                && topology.display(for: server.frame)?.id == display?.id
        }
        guard !near.isEmpty else {
            planningDone = true
            return
        }
        let apps = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications
            .filter { app in near.contains { $0.pid == app.processIdentifier } }
            .map { ($0.processIdentifier, RunningApplicationInfo(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier,
                                                                 name: $0.localizedName ?? "?", isHidden: $0.isHidden)) })
        Task { [weak self, repository, policy] in
            var candidates: [LinkedResize.Candidate] = []
            for server in near {
                guard let app = apps[server.pid], let snapshot = await repository.resolve(server, app: app),
                      case .eligible(resizable: true) = policy.evaluate(snapshot) else { continue }
                candidates.append(.init(token: snapshot.token, frame: snapshot.frame))
            }
            guard let self, self.session == session else { return }
            for edge in LinkedResize.Edge.allCases {
                let plan = LinkedResize.plan(driver: original, edge: edge, candidates: candidates)
                if !plan.isEmpty { self.plans[edge] = plan }
            }
            self.planningDone = true
            Log.snapGroups.debug("Linked resize: \(self.plans.values.reduce(0) { $0 + $1.followers.count }) follower(s)")
            self.flush()
        }
    }

    public func update(session: SnapSessionID, current: CGRect) {
        guard session == self.session else { return }
        latest = current
        flush()
    }

    private func activePlans(for current: CGRect) -> [LinkedResize.Plan] {
        LinkedResize.movedEdges(original: original, current: current).compactMap { plans[$0] }
    }

    private func flush() {
        guard planningDone, !writeInFlight, let current = latest, let session else { return }
        latest = nil
        let active = activePlans(for: current)
        guard !active.isEmpty else { return }
        let frames = LinkedResize.followerFrames(plans: active, driverOriginal: original, driverCurrent: current)
        writeInFlight = true
        let clock = ContinuousClock(), start = clock.now
        Task { [weak self, geometry] in
            await geometry.applyLive(frames)
            PerformanceMonitor.shared.record("linkedResize.liveWrite", milliseconds: (clock.now - start).milliseconds)
            guard let self, self.session == session else { return }
            self.writeInFlight = false
            self.flush()
        }
    }

    public func end(session: SnapSessionID, final: CGRect) {
        guard session == self.session, let driver else { return }
        self.session = nil
        let active = activePlans(for: final)
        guard !active.isEmpty else { return }
        let frames = LinkedResize.followerFrames(plans: active, driverOriginal: original, driverCurrent: final)
        Task { [repository, geometry] in
            var actual: [WindowToken: CGRect] = [:]
            for (token, frame) in frames {
                if let result = try? await geometry.apply(frame, to: token) { actual[token] = result.actualFrame }
            }
            if actual.count < frames.count {
                // Re-read what we could not verify (e.g. adjusted by the app).
                let missing = frames.keys.filter { actual[$0] == nil }
                actual.merge(await repository.frames(of: Array(missing))) { a, _ in a }
            }
            if let corrected = LinkedResize.driverCorrection(plans: active, driverCurrent: final, followerActual: actual) {
                _ = try? await geometry.apply(corrected, to: driver.token)
                Log.snapGroups.info("Linked resize: driver pulled back to a follower's minimum size")
            }
        }
    }
}
