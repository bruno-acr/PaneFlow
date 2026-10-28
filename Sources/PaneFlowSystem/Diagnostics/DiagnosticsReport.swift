import Foundation

/// Sanitised diagnostics. Contains no window titles, document names or images.
public struct DiagnosticsReport: Sendable, Codable {
    public struct Display: Sendable, Codable {
        public let frame: String
        public let visibleFrame: String
        public let scale: Double
        public let isPrimary: Bool

        public init(frame: String, visibleFrame: String, scale: Double, isPrimary: Bool) {
            self.frame = frame
            self.visibleFrame = visibleFrame
            self.scale = scale
            self.isPrimary = isPrimary
        }
    }

    public let generatedAt: Date
    public let appVersion: String
    public let osVersion: String
    public let architecture: String
    public let permissions: [String: Bool]
    public let displays: [Display]
    public let nativeWindowManager: NativeWindowManagerSettings
    public let performance: [PerformanceMonitor.Summary]
    public let notes: [String]

    public init(
        permissions: [String: Bool], displays: [Display],
        nativeWindowManager: NativeWindowManagerSettings, notes: [String] = []
    ) {
        generatedAt = Date()
        appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") + ")"
        osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        architecture = "arm64"
        #else
        architecture = "x86_64"
        #endif
        self.permissions = permissions
        self.displays = displays
        self.nativeWindowManager = nativeWindowManager
        performance = PerformanceMonitor.shared.summaries()
        self.notes = notes
    }

    /// Directory for locally written reports. Nothing is ever uploaded.
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "PaneFlow/Diagnostics", directoryHint: .isDirectory)
    }

    public static func write<T: Encodable>(_ value: T, named prefix: String) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = directory.appending(path: "\(prefix)-\(stamp).json")
        try encoder.encode(value).write(to: url, options: .atomic)
        return url
    }
}
