import Foundation

/// The complete state of the app, written to one JSON file so a new Mac needs a single import.
public struct Export: Hashable, Sendable {
    public var exportedAt: Date
    public var layout: Layout
    public var preferences: Preferences

    public init(exportedAt: Date, layout: Layout, preferences: Preferences) {
        self.exportedAt = exportedAt
        self.layout = layout
        self.preferences = preferences
    }

    /// The export file's content: UTF-8 JSON with `schemaVersion`, `exportedAt` in ISO 8601 UTC, `layout`, and
    /// `preferences`. ISO 8601 keeps whole seconds only.
    public func jsonData() throws -> Data {
        try JSONFormat.makeEncoder().encode(
            ExportFile(
                schemaVersion: JSONFormat.schemaVersion,
                exportedAt: exportedAt,
                layout: layout,
                preferences: preferences
            )
        )
    }

    /// Reads an export file. Throws `PersistenceError.unsupportedSchemaVersion` for a file from a newer
    /// MacStart, and `PersistenceError.malformedData` for anything else that does not match the format.
    public init(jsonData: Data) throws(PersistenceError) {
        let file = try JSONFormat.decode(ExportFile.self, from: jsonData)
        self.init(exportedAt: file.exportedAt, layout: file.layout, preferences: file.preferences)
    }
}

private struct ExportFile: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let layout: Layout
    let preferences: Preferences
}
