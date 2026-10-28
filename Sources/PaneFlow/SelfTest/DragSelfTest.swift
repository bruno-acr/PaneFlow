import AppKit
import ApplicationServices
import PaneFlowCore
import PaneFlowSystem

/// End-to-end test of drag snapping and linked resizing with **synthetic mouse events** posted to the
/// HID stream, observed by the same global monitors used in normal operation.
///
/// Safety rules: moves use a Finder window on a fresh empty temporary folder (dragging inside it only
/// draws a selection rectangle; there are no files to drag). Before pressing the mouse, the element
/// under the cursor is hit-tested and buttons/text fields are refused. Linked resize grabs the shared
/// edge between Safari and Word, which never touches document content. All frames are restored.
@MainActor
struct DragSelfTest {
    typealias Check = Phase1SelfTest.Check

    struct Report: Encodable {
        let generatedAt = Date()
        let nativeEdgeTilingEnabled: Bool?
        var otherWindowManagers: [String] = []
        let checks: [Check]
        var passed: Bool { !checks.isEmpty && checks.allSatisfy(\.passed) }

        enum CodingKeys: String, CodingKey { case generatedAt, nativeEdgeTilingEnabled, otherWindowManagers, checks, passed }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(generatedAt, forKey: .generatedAt)
            try c.encode(nativeEdgeTilingEnabled, forKey: .nativeEdgeTilingEnabled)
            try c.encode(otherWindowManagers, forKey: .otherWindowManagers)
            try c.encode(checks, forKey: .checks)
            try c.encode(passed, forKey: .passed)
        }
    }

    let repository: WindowRepository
    let geometry: WindowGeometryController
    let topology: DisplayTopology
    /// Zones committed by `SnapController` since the last reset.
    let commits: () -> [SnapZone]
    let resetCommits: () -> Void
    let setAssistEnabled: (Bool) -> Void
    let assistState: () -> (showing: Bool, candidates: Int)
    let assistSelection: () -> WindowToken?
    let swap: (WindowSnapshot) async -> Void

    private let source = CGEventSource(stateID: .hidSystemState)

    // MARK: Synthetic input

    private func post(_ type: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

    private func drag(from a: CGPoint, to b: CGPoint, steps: Int, stepMs: Int) async {
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            await pause(stepMs)
        }
    }

    private func pressEscape() {
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private func roleAt(_ p: CGPoint) async -> String? {
        await AccessibilityExecutor.shared.perform { AXElement.element(at: p)?.string(kAXRoleAttribute) }
    }

    private func frame(_ token: WindowToken) async -> CGRect? {
        await repository.frames(of: [token])[token]
    }

    // MARK: Run

    func run() async -> Report {
        var checks: [Check] = []
        let native = NativeWindowManagerSettings.read().edgeDragTilingEnabled
        guard AXIsProcessTrusted() else {
            return Report(nativeEdgeTilingEnabled: native, checks: [Check(name: "accessibility", passed: false, detail: "not granted")])
        }
        guard let mac = topology.primary else {
            return Report(nativeEdgeTilingEnabled: native, checks: [Check(name: "displays", passed: false, detail: "no display")])
        }
        let originalCursor = CGEvent(source: nil)?.location ?? mac.frame.center

        // Finder window on an empty temporary folder.
        let folder = FileManager.default.temporaryDirectory.appending(path: "PaneFlow-Teste-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        NSWorkspace.shared.open(folder)

        var finder: WindowSnapshot?
        for _ in 0..<20 where finder == nil {
            await pause(250)
            finder = await windows(bundle: "com.apple.finder").first { $0.title == folder.lastPathComponent }
        }
        if let finder {
            checks += await moveTests(finder, mac: mac)
            await closeWindow(finder.token)
        } else {
            checks.append(Check(name: "finder-window", passed: false, detail: "test window did not appear"))
        }

        checks += await linkedResizeTest(on: mac)

        post(.mouseMoved, originalCursor)
        return Report(nativeEdgeTilingEnabled: native, otherWindowManagers: ConflictingWindowManagers.running(), checks: checks)
    }

    private func windows(bundle: String) async -> [WindowSnapshot] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundle }.map {
            RunningApplicationInfo(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier,
                                   name: $0.localizedName ?? "?", isHidden: $0.isHidden)
        }
        return await repository.discoverWindows(of: apps)
    }

    private func closeWindow(_ token: WindowToken) async {
        guard let element = repository.element(for: token) else { return }
        _ = await AccessibilityExecutor.shared.perform {
            (try? element.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)) != nil
        }
    }

    // MARK: Move / snap tests

    private func moveTests(_ window: WindowSnapshot, mac: DisplayDescriptor) async -> [Check] {
        let floating = LayoutEngine.centered(size: CGSize(width: 640, height: 420), in: mac.visibleFrame)
        let midY = mac.visibleFrame.midY
        let sharedLeft = topology.displays.contains { abs($0.frame.maxX - mac.frame.minX) <= 1 && midY >= $0.frame.minY && midY <= $0.frame.maxY }
        var checks: [Check] = []

        checks.append(await moveCase("drag-to-right-edge", window, floating,
                                     target: CGPoint(x: mac.frame.maxX - 1, y: midY), dwellMs: 150,
                                     expect: SnapZone(region: .rightHalf, displayID: mac.id)))
        checks.append(await moveCase("drag-to-top-edge", window, floating,
                                     target: CGPoint(x: mac.frame.midX, y: mac.frame.minY + 1), dwellMs: 150,
                                     expect: SnapZone(region: .maximize, displayID: mac.id)))
        if sharedLeft {
            checks.append(await pushCase("push-against-shared-edge-snaps", window, floating, mac: mac,
                                         pushes: 14, expect: SnapZone(region: .leftHalf, displayID: mac.id)))
            checks.append(await pushCase("push-through-shared-edge-moves-to-neighbour", window, floating, mac: mac,
                                         pushes: 70, expect: nil))
            checks.append(await moveCase("shared-edge-stop-inside", window, floating,
                                         target: CGPoint(x: mac.frame.minX + 15, y: midY), dwellMs: 400,
                                         expect: SnapZone(region: .leftHalf, displayID: mac.id)))
            checks.append(await moveCase("shared-edge-overshoot-into-neighbour", window, floating,
                                         target: CGPoint(x: mac.frame.minX - 35, y: midY), dwellMs: 400,
                                         expect: SnapZone(region: .leftHalf, displayID: mac.id)))
            checks.append(await moveCase("fast-crossing-does-not-snap", window, floating,
                                         target: CGPoint(x: mac.frame.minX - 700, y: midY), dwellMs: 100,
                                         expect: nil, fast: true))
        }
        checks.append(await moveCase("escape-cancels", window, floating,
                                     target: CGPoint(x: mac.frame.maxX - 1, y: midY), dwellMs: 150,
                                     expect: nil, escape: true))
        checks.append(await contentDragCase(window, floating, target: CGPoint(x: mac.frame.maxX - 1, y: midY)))
        checks.append(await snapAssistCase(window, floating, target: CGPoint(x: mac.frame.maxX - 1, y: midY)))
        checks.append(await snapAssistChooseCase(window, floating, target: CGPoint(x: mac.frame.maxX - 1, y: midY), mac: mac))
        return checks
    }

    /// Like a physical mouse: relative steps of 6 pt to the left from wherever the cursor currently is,
    /// so edge resistance can hold the cursor back. 14 pushes stay within the resistance; 70 break through.
    private func pushCase(_ name: String, _ window: WindowSnapshot, _ start: CGRect, mac: DisplayDescriptor,
                          pushes: Int, expect: SnapZone?) async -> Check {
        guard (try? await geometry.apply(start, to: window.token)) != nil else {
            return Check(name: name, passed: false, detail: "could not place test window")
        }
        await pause(250)
        guard let grab = await grabPoint(start) else { return Check(name: name, passed: false, detail: "no safe drag point") }
        resetCommits()
        post(.mouseMoved, grab)
        await pause(50)
        post(.leftMouseDown, grab)
        await pause(80)
        // Approach the shared edge: stop 30 pt before it.
        let approach = CGPoint(x: mac.frame.minX + 30, y: mac.visibleFrame.midY)
        await drag(from: grab, to: approach, steps: 30, stepMs: 16)
        await pause(100)
        var minX = CGFloat.greatestFiniteMagnitude
        for _ in 0..<pushes {
            let current = CGEvent(source: nil)?.location ?? approach
            minX = min(minX, current.x)
            post(.leftMouseDragged, CGPoint(x: current.x - 6, y: current.y))
            await pause(16)
        }
        await pause(250)
        let release = CGEvent(source: nil)?.location ?? approach
        post(.leftMouseUp, release)
        await pause(600)
        let committed = commits()
        let final = await frame(window.token)
        var passed = committed == (expect.map { [$0] } ?? [])
        if let expect, let expected = expect.frame(in: topology), let final {
            passed = passed && GeometryVerifier.verify(requested: expected, actual: final).isAcceptable
        } else if expect == nil {
            passed = passed && release.x < mac.frame.minX // the cursor really crossed to the neighbour
        }
        return Check(name: name, passed: passed,
                     detail: "release \(Int(release.x)),\(Int(release.y)) commits=\(committed.map { "\($0.region.rawValue)@\($0.displayID)" }) final \(final.map(NSStringFromRect) ?? "nil")")
    }

    /// Finds a point in the title/toolbar strip that drags the window, refusing controls.
    private func grabPoint(_ frame: CGRect) async -> CGPoint? {
        let refused: Set<String> = ["AXButton", "AXTextField", "AXSearchField", "AXPopUpButton", "AXMenuButton",
                                    "AXRadioButton", "AXCheckBox", "AXSegmentedControl", "AXLink", "AXRow", "AXCell"]
        for dy in [CGFloat(12), 26, 40] {
            for fx in [CGFloat(0.5), 0.6, 0.4, 0.7, 0.3] {
                let p = CGPoint(x: frame.minX + frame.width * fx, y: frame.minY + dy)
                if let role = await roleAt(p), !refused.contains(role) { return p }
            }
        }
        return nil
    }

    private func moveCase(
        _ name: String, _ window: WindowSnapshot, _ start: CGRect, target: CGPoint, dwellMs: Int,
        expect: SnapZone?, fast: Bool = false, escape: Bool = false
    ) async -> Check {
        guard (try? await geometry.apply(start, to: window.token)) != nil else {
            return Check(name: name, passed: false, detail: "could not place test window")
        }
        await pause(250)
        guard let grab = await grabPoint(start) else {
            return Check(name: name, passed: false, detail: "no safe drag point in title bar")
        }
        resetCommits()
        post(.mouseMoved, grab)
        await pause(50)
        post(.leftMouseDown, grab)
        await pause(80)
        let nudge = CGPoint(x: grab.x + 40, y: grab.y + 10)
        await drag(from: grab, to: nudge, steps: 4, stepMs: 20)
        await pause(120)
        let moved = await frame(window.token).map { abs($0.minX - start.minX) > 20 } ?? false
        if fast {
            await drag(from: nudge, to: target, steps: 10, stepMs: 8)
        } else {
            await drag(from: nudge, to: target, steps: 30, stepMs: 16)
        }
        await pause(dwellMs)
        if escape {
            pressEscape()
            await pause(100)
        }
        post(.leftMouseUp, target)
        await pause(600)

        let committed = commits()
        let final = await frame(window.token)
        var passed = moved && committed == (expect.map { [$0] } ?? [])
        var detail = "windowFollowedCursor=\(moved) commits=\(committed.map { "\($0.region.rawValue)@\($0.displayID)" })"
        if let expect, let expected = expect.frame(in: topology), let final {
            let verdict = GeometryVerifier.verify(requested: expected, actual: final)
            passed = passed && verdict.isAcceptable
            detail += " expected \(NSStringFromRect(expected)) actual \(NSStringFromRect(final))"
        } else if let final {
            detail += " final \(NSStringFromRect(final))"
        }
        return Check(name: name, passed: passed, detail: detail)
    }

    /// Snapping to the right half must open Snap Assist over the left half; Escape closes it.
    private func snapAssistCase(_ window: WindowSnapshot, _ start: CGRect, target: CGPoint) async -> Check {
        setAssistEnabled(true)
        defer { setAssistEnabled(false) }
        let snapped = await moveCase("snap-assist-snap", window, start, target: target, dwellMs: 150,
                                     expect: SnapZone(region: .rightHalf, displayID: topology.primary?.id ?? 0))
        var opened = false
        for _ in 0..<15 where !opened {
            await pause(100)
            opened = assistState().showing
        }
        let candidates = assistState().candidates
        pressEscape()
        await pause(300)
        let closed = !assistState().showing
        return Check(name: "snap-assist-opens-and-escape-closes", passed: snapped.passed && opened && candidates > 0 && closed,
                     detail: "snapped=\(snapped.passed) opened=\(opened) candidates=\(candidates) closedByEscape=\(closed)")
    }

    /// Choosing a candidate with ↩ must fill exactly the space left next to the snapped window.
    private func snapAssistChooseCase(_ window: WindowSnapshot, _ start: CGRect, target: CGPoint, mac: DisplayDescriptor) async -> Check {
        let name = "snap-assist-choice-fills-empty-space"
        setAssistEnabled(true)
        defer { setAssistEnabled(false) }
        _ = await moveCase("snap-assist-snap-2", window, start, target: target, dwellMs: 150,
                           expect: SnapZone(region: .rightHalf, displayID: mac.id))
        var chosen: WindowToken?
        for _ in 0..<15 where chosen == nil {
            await pause(100)
            chosen = assistSelection()
        }
        guard let chosen, let before = await frame(chosen) else {
            pressEscape()
            return Check(name: name, passed: false, detail: "Snap Assist did not show a candidate")
        }
        CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)?.post(tap: .cghidEventTap)
        await pause(1200)
        let frames = await repository.frames(of: [chosen, window.token])
        defer { Task { @MainActor [geometry] in _ = try? await geometry.apply(before, to: chosen) } }
        guard let c = frames[chosen], let snapped = frames[window.token] else {
            return Check(name: name, passed: false, detail: "windows vanished")
        }
        let area = mac.visibleFrame
        let noOverlap = c.intersectionArea(with: snapped) <= 1
        let noHole = abs(c.maxX - snapped.minX) <= 2
        let reachesEdge = abs(c.minX - area.minX) <= 2 && abs(c.minY - area.minY) <= 2 && abs(c.maxY - area.maxY) <= 2
        return Check(name: name, passed: noOverlap && noHole && reachesEdge && !assistState().showing,
                     detail: "chosen \(NSStringFromRect(c)) snapped \(NSStringFromRect(snapped)) noOverlap=\(noOverlap) noHole=\(noHole) edge=\(reachesEdge)")
    }

    /// Dragging inside the window's content must never move or snap it.
    private func contentDragCase(_ window: WindowSnapshot, _ start: CGRect, target: CGPoint) async -> Check {
        // Use the frame the app actually adopted (Finder imposes a minimum width).
        guard let start = (try? await geometry.apply(start, to: window.token))?.actualFrame else {
            return Check(name: "content-drag-does-not-snap", passed: false, detail: "could not place test window")
        }
        await pause(250)
        let p = CGPoint(x: start.midX + 60, y: start.midY + 60)
        let role = await roleAt(p) ?? "?"
        guard !["AXButton", "AXTextField", "AXLink"].contains(role) else {
            return Check(name: "content-drag-does-not-snap", passed: false, detail: "unsafe content point (\(role))")
        }
        resetCommits()
        post(.mouseMoved, p)
        await pause(50)
        post(.leftMouseDown, p)
        await pause(80)
        await drag(from: p, to: target, steps: 30, stepMs: 16)
        await pause(200)
        post(.leftMouseUp, target)
        await pause(500)
        let final = await frame(window.token)
        let unchanged = final.map { $0.isApproximatelyEqual(to: start, tolerance: 2) } ?? false
        return Check(name: "content-drag-does-not-snap", passed: unchanged && commits().isEmpty,
                     detail: "role=\(role) commits=\(commits().count) unchanged=\(unchanged) start \(NSStringFromRect(start)) final \(final.map(NSStringFromRect) ?? "nil")")
    }

    // MARK: Linked resize

    private func linkedResizeTest(on mac: DisplayDescriptor) async -> [Check] {
        guard let safari = await windows(bundle: "com.apple.Safari").first(where: { $0.subrole == "AXStandardWindow" && !$0.isMinimized }),
              let word = await windows(bundle: "com.microsoft.Word").first(where: { $0.subrole == "AXStandardWindow" && !$0.isMinimized })
        else {
            return [Check(name: "linked-resize", passed: false, detail: "Safari and Word windows required")]
        }
        let originals = [(safari.token, safari.frame), (word.token, word.frame)]
        defer {
            Task { @MainActor [geometry] in
                for (token, frame) in originals { _ = try? await geometry.apply(frame, to: token) }
            }
        }
        let halves = LayoutEngine.frames(for: LayoutCatalog.halves, in: mac.visibleFrame)
        _ = try? await geometry.apply(halves[1], to: word.token)
        _ = try? await geometry.apply(halves[0], to: safari.token)
        // Safari in front so its edge owns the resize handle.
        if let element = repository.element(for: safari.token) {
            _ = await AccessibilityExecutor.shared.perform { (try? element.perform(kAXRaiseAction)) != nil }
        }
        NSRunningApplication(processIdentifier: safari.pid)?.activate()
        await pause(500)

        let boundary = halves[0].maxX
        let grab = CGPoint(x: boundary + 2, y: halves[0].midY)
        let target = CGPoint(x: (mac.visibleFrame.minX + mac.visibleFrame.width * 0.4).rounded(), y: grab.y)
        post(.mouseMoved, grab)
        await pause(80)
        post(.leftMouseDown, grab)
        await pause(80)
        let mid = CGPoint(x: (grab.x + target.x) / 2, y: grab.y)
        await drag(from: grab, to: mid, steps: 15, stepMs: 16)
        await pause(150)
        let midFrames = await repository.frames(of: [safari.token, word.token])
        await drag(from: mid, to: target, steps: 15, stepMs: 16)
        await pause(150)
        post(.leftMouseUp, target)
        await pause(900)
        let end = await repository.frames(of: [safari.token, word.token])

        guard let s = end[safari.token], let w = end[word.token], let sm = midFrames[safari.token], let wm = midFrames[word.token] else {
            return [Check(name: "linked-resize", passed: false, detail: "windows vanished")]
        }
        let driverResized = abs(s.maxX - boundary) > 40 || abs(w.minX - boundary) > 40
        let liveFollow = abs(wm.minX - sm.maxX) <= 4
        let together = abs(w.minX - s.maxX) <= 3
        let farEdgesKept = abs(s.minX - halves[0].minX) <= 2 && abs(w.maxX - halves[1].maxX) <= 2
        // Swap: Safari and Word exchange sides, keeping their widths.
        var swapCheck = Check(name: "swap-windows", passed: false, detail: "skipped")
        if let safariNow = try? await repository.snapshot(of: safari.token) {
            await swap(safariNow)
            await pause(400)
            let swapped = await repository.frames(of: [safari.token, word.token])
            if let s2 = swapped[safari.token], let w2 = swapped[word.token] {
                let ok = abs(s2.maxX - mac.visibleFrame.maxX) <= 3 && abs(w2.minX - mac.visibleFrame.minX) <= 3
                    && abs(s2.width - s.width) <= 3 && abs(w2.width - w.width) <= 3
                swapCheck = Check(name: "swap-windows", passed: ok,
                                  detail: "after swap safari \(NSStringFromRect(s2)) word \(NSStringFromRect(w2))")
            }
        }
        return [
            swapCheck,
            Check(name: "linked-resize-edge-grabbed", passed: driverResized,
                  detail: "safari \(NSStringFromRect(s)) word \(NSStringFromRect(w))"),
            Check(name: "linked-resize-follows-live", passed: driverResized && liveFollow,
                  detail: "mid-drag safari.maxX=\(sm.maxX) word.minX=\(wm.minX)"),
            Check(name: "linked-resize-final", passed: driverResized && together && farEdgesKept,
                  detail: "final safari.maxX=\(s.maxX) word.minX=\(w.minX) far edges kept=\(farEdgesKept)"),
        ]
    }
}
