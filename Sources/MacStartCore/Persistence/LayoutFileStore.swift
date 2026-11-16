import Foundation

/// Reads and writes `layout.json`. The calls do file I/O, so run them off the main actor.
public struct LayoutFileStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/MacStart/layout.json`.
    public static let standardFileURL = URL.applicationSupportDirectory.appending(
        components: "MacStart",
        "layout.json",
        directoryHint: .notDirectory
    )

    /// The stored layout, or nil when no layout was saved yet. Throws `PersistenceError` for a file it
    /// cannot read, and the file system's error when the file cannot be opened.
    public func load() throws -> Layout? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        return try JSONFormat.decode(LayoutFile.self, from: data).layout
    }

    /// Writes the layout atomically, so a crash never leaves a half-written file. Creates the folder if needed.
    public func save(_ layout: Layout) throws {
        let data = try JSONFormat.makeEncoder().encode(
            LayoutFile(schemaVersion: JSONFormat.schemaVersion, layout: layout))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Renames an unreadable file to `layout.unreadable-<UTC time>.json` in the same folder, so the next save
    /// does not overwrite it, for example a file from a newer MacStart. Returns the new location.
    public func moveUnreadableFileAside(at date: Date = .now) throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        let name = fileURL.deletingPathExtension().lastPathComponent
        let destination = fileURL.deletingLastPathComponent().appending(
            path: "\(name).unreadable-\(formatter.string(from: date)).\(fileURL.pathExtension)",
            directoryHint: .notDirectory
        )
        try FileManager.default.moveItem(at: fileURL, to: destination)
        return destination
    }
}

/// The content of `layout.json`.
private struct LayoutFile: Codable {
    let schemaVersion: Int
    let layout: Layout
}
