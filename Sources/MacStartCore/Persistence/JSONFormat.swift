import Foundation

/// Why a layout file, export file, or stored preferences value could not be read.
public enum PersistenceError: Error {
    /// The data has a schema version this build cannot read, usually one written by a newer MacStart.
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// The data is not valid JSON, or its content does not match the format.
    case malformedData(underlying: any Error)
}

/// The JSON settings shared by `layout.json`, export files, and stored preferences.
enum JSONFormat {
    /// The current schema version of every format. Bump it on any format change, and add a migration for
    /// the old version in `decode(_:from:)`, covered by a fixture test.
    static let schemaVersion = 1

    /// Pretty-printed, with sorted keys, so the same value always produces the same, readable file.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Checks `schemaVersion` before decoding the rest, so a newer file is reported as such instead of as
    /// malformed.
    static func decode<Document: Decodable>(_: Document.Type, from data: Data) throws(PersistenceError) -> Document {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        } catch {
            throw .malformedData(underlying: error)
        }
        // Older versions get an explicit migration here once the format changes for the first time.
        guard version == schemaVersion else {
            throw .unsupportedSchemaVersion(found: version, supported: schemaVersion)
        }

        do {
            return try decoder.decode(Document.self, from: data)
        } catch {
            throw .malformedData(underlying: error)
        }
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }
}
