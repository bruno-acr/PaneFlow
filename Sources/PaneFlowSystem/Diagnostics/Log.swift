import OSLog

/// OSLog categories. Window titles and document names must only be logged with
/// `privacy: .private` (redacted in persisted logs by default).
public enum Log {
    public static let subsystem = "app.paneflow.PaneFlow"

    public static let lifecycle = Logger(subsystem: subsystem, category: "app.lifecycle")
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")
    public static let discovery = Logger(subsystem: subsystem, category: "window.discovery")
    public static let geometry = Logger(subsystem: subsystem, category: "window.geometry")
    public static let snapDetection = Logger(subsystem: subsystem, category: "snap.detection")
    public static let snapTransaction = Logger(subsystem: subsystem, category: "snap.transaction")
    public static let snapAssist = Logger(subsystem: subsystem, category: "snap.assist")
    public static let snapGroups = Logger(subsystem: subsystem, category: "snap.groups")
    public static let displays = Logger(subsystem: subsystem, category: "displays")
    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let performance = Logger(subsystem: subsystem, category: "performance")
    public static let errors = Logger(subsystem: subsystem, category: "errors")
}
