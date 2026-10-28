import AppKit
import PaneFlowSystem

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: ApplicationCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launch = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        let coordinator = ApplicationCoordinator(launchOptions: launch)
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.lifecycle.info("PaneFlow terminating")
    }
}

/// Command-line switches, used by automated validation (`scripts/self-test.sh`).
struct LaunchOptions {
    /// Run the Phase 1 geometry self-test, write the report and quit.
    var runSelfTest = false
    /// Keep the test layout instead of restoring the original frames afterwards.
    var keepSelfTestLayout = false
    var selfTestOutput: URL?
    /// Run the end-to-end drag test (synthetic mouse events), write the report and quit.
    var runDragTest = false

    init(arguments: [String]) {
        runSelfTest = arguments.contains("--self-test")
        keepSelfTestLayout = arguments.contains("--self-test-keep")
        runDragTest = arguments.contains("--drag-test")
        if let index = arguments.firstIndex(of: "--self-test-output"), index + 1 < arguments.count {
            selfTestOutput = URL(fileURLWithPath: arguments[index + 1])
        }
    }
}
