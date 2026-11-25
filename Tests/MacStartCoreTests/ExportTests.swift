import Foundation
import MacStartCore
import Testing

@Suite("Export and import")
struct ExportTests {
    let sample = Fixtures.exportV1Content

    @Test func roundTripKeepsEverything() throws {
        let decoded = try Export(jsonData: sample.jsonData())

        #expect(decoded == sample)
        // `AppID` equality ignores bundle identifiers, so compare them separately.
        #expect(
            decoded.layout.placedAppIDs.map(\.bundleIdentifier) == sample.layout.placedAppIDs.map(\.bundleIdentifier))
        #expect(decoded.layout.hidden.map(\.bundleIdentifier) == sample.layout.hidden.map(\.bundleIdentifier))
    }

    @Test func readsAVersion1File() throws {
        let decoded = try Export(jsonData: Data(Fixtures.exportV1.utf8))

        #expect(decoded == Fixtures.exportV1Content)
        #expect(decoded.layout.placedAppIDs.map(\.bundleIdentifier) == ["com.apple.Safari", "com.apple.Notes", nil])
    }

    @Test func writesTheDocumentedFormat() throws {
        let data = try sample.jsonData()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let preferences = try #require(object["preferences"] as? [String: Any])
        let hotKey = try #require(preferences["hotKey"] as? [String: Any])

        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["exportedAt"] as? String == "2026-11-16T12:00:00Z")
        #expect(hotKey["modifiers"] as? [String] == ["control", "option"])
        #expect(String(decoding: data, as: UTF8.self).contains("\"/Applications/Safari.app\""))
        #expect(try sample.jsonData() == data)
    }

    @Test func writesHiddenAppsSortedByPath() throws {
        var export = sample
        export.layout.hidden = [appID("Zebra"), appID("Alpha"), appID("Mango")]

        let object = try #require(try JSONSerialization.jsonObject(with: export.jsonData()) as? [String: Any])
        let layout = try #require(object["layout"] as? [String: Any])
        let hidden = try #require(layout["hidden"] as? [[String: Any]])

        #expect(
            hidden.compactMap { $0["path"] as? String }
                == ["Alpha", "Mango", "Zebra"].map { "/Applications/\($0).app" })
    }

    @Test func rejectsANewerSchemaVersion() {
        let json = Fixtures.exportV1.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 2")

        let error = #expect(throws: PersistenceError.self) { try Export(jsonData: Data(json.utf8)) }

        guard case .unsupportedSchemaVersion(let found, let supported)? = error else {
            Issue.record("Expected unsupportedSchemaVersion, got \(String(describing: error))")
            return
        }
        #expect(found == 2)
        #expect(supported == 1)
    }

    @Test(arguments: [
        "not json",
        "{}",
        #"{ "schemaVersion" : "1" }"#,
        #"{ "schemaVersion" : 1 }"#,
    ])
    func rejectsMalformedFiles(json: String) {
        let error = #expect(throws: PersistenceError.self) { try Export(jsonData: Data(json.utf8)) }

        guard case .malformedData? = error else {
            Issue.record("Expected malformedData, got \(String(describing: error))")
            return
        }
    }

    @Test(arguments: [
        (#""path" : "/Applications/Safari.app""#, #""path" : "Applications/Safari.app""#),
        (#"[ "control", "option" ]"#, #"[ "control", "hyper" ]"#),
        (#"{ "app" : { "bundleIdentifier" : "com.apple.Safari", "path" : "/Applications/Safari.app" } }"#, "{ }"),
    ])
    func rejectsInvalidContent(original: String, replacement: String) {
        #expect(Fixtures.exportV1.contains(original))
        let json = Fixtures.exportV1.replacingOccurrences(of: original, with: replacement)

        let error = #expect(throws: PersistenceError.self) { try Export(jsonData: Data(json.utf8)) }

        guard case .malformedData? = error else {
            Issue.record("Expected malformedData, got \(String(describing: error))")
            return
        }
    }

    @Test func importMovesAGridSizeThatIsNotAllowedToTheNearestAllowedOne() throws {
        #expect(Fixtures.exportV1.contains(#""gridColumns" : 8"#))
        let json = Fixtures.exportV1
            .replacingOccurrences(of: #""gridColumns" : 8"#, with: #""gridColumns" : 15"#)
            .replacingOccurrences(of: #""gridRows" : 6"#, with: #""gridRows" : 2"#)

        let export = try Export(jsonData: Data(json.utf8))

        #expect(export.preferences.gridSize == GridSize(columns: 7, rows: 4))
    }

    @Test func aSnapshotKeepsWholeSecondsSoItSurvivesTheRoundTrip() throws {
        let export = Export.snapshot(
            layout: sample.layout,
            preferences: sample.preferences,
            at: Date(timeIntervalSince1970: 1_794_830_400.75)
        )

        #expect(export.exportedAt == Date(timeIntervalSince1970: 1_794_830_400))
        #expect(try Export(jsonData: export.jsonData()) == export)
    }
}
