// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaneFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PaneFlow", targets: ["PaneFlow"]),
    ],
    targets: [
        // Pure decision logic: geometry, layouts, identity correlation. No AppKit.
        .target(name: "PaneFlowCore"),
        // Operating-system integration: Accessibility, displays, permissions, logging.
        .target(name: "PaneFlowSystem", dependencies: ["PaneFlowCore"]),
        // Resident menu-bar application.
        .executableTarget(name: "PaneFlow", dependencies: ["PaneFlowCore", "PaneFlowSystem"]),
        .testTarget(name: "PaneFlowCoreTests", dependencies: ["PaneFlowCore"]),
        .testTarget(name: "PaneFlowSystemTests", dependencies: ["PaneFlowSystem"]),
    ]
)
