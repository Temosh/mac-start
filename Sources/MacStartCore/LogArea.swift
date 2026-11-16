import os

/// The areas MacStart logs under. Each area is one `os.Logger` category in the
/// `cc.summ.MacStart` subsystem, so Console can filter the logs by area.
public enum LogArea: String, CaseIterable, Sendable {
    case catalog
    case layout
    case overlay
    case hotkey

    /// The logging subsystem shared by every module. It matches the bundle identifier.
    public static let subsystem = "cc.summ.MacStart"

    /// A logger for this area.
    public var logger: Logger {
        Logger(subsystem: Self.subsystem, category: rawValue)
    }
}
