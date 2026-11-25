import Foundation
import MacStartCore
import Testing

@Suite("Preferences")
struct PreferencesTests {
    @Test func defaultsMatchTheSpec() {
        let preferences = Preferences.default

        #expect(preferences.hotKey == HotKey(keyCode: 0x01, modifiers: [.option]))
        #expect(preferences.gridColumns == 7)
        #expect(preferences.gridRows == 5)
        #expect(preferences.launchAtLogin)
        #expect(preferences.pageCapacity == 35)
    }

    @Test func settingsOffersNineGridSizes() {
        #expect(
            Preferences.allowedGridSizes.map(\.text) == [
                "5 × 4", "6 × 4", "7 × 4", "6 × 5", "7 × 5", "8 × 5", "7 × 6", "8 × 6", "9 × 6",
            ]
        )
    }

    @Test func aGridSizeThatIsNotAllowedBecomesTheNearestAllowedOne() {
        var preferences = Preferences(hotKey: .default, gridColumns: 99, gridRows: 0, launchAtLogin: true)
        #expect(preferences.gridSize == GridSize(columns: 7, rows: 4))

        preferences.gridSize = GridSize(columns: 1, rows: 50)
        #expect(preferences.gridSize == GridSize(columns: 7, rows: 6))

        preferences.gridSize = GridSize(columns: 9, rows: 5)
        #expect(preferences.gridSize == GridSize(columns: 8, rows: 5))

        preferences.gridSize = GridSize(columns: 5, rows: 6)
        #expect(preferences.gridSize == GridSize(columns: 7, rows: 6))
    }

    @Test func changingColumnsAndRowsTogetherKeepsBoth() {
        var preferences = Preferences(hotKey: .default, gridColumns: 5, gridRows: 4, launchAtLogin: true)

        preferences.gridSize = GridSize(columns: 9, rows: 6)

        #expect(preferences.gridSize == GridSize(columns: 9, rows: 6))
    }

    @Test func readingMovesAGridSizeThatIsNotAllowedToTheNearestAllowedOne() throws {
        let saved = Preferences(hotKey: .default, gridColumns: 7, gridRows: 5, launchAtLogin: true)
        var json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any]
        )
        json["gridColumns"] = 9
        json["gridRows"] = 4

        let read = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(read.gridSize == GridSize(columns: 7, rows: 4))
        #expect(read.hotKey == saved.hotKey)
    }

    @Test func storeLoadsNilBeforeTheFirstSave() {
        #expect(PreferencesStore(storage: InMemoryStorage()).load() == nil)
    }

    @Test func storeKeepsSavedPreferences() throws {
        let store = PreferencesStore(storage: InMemoryStorage())
        let preferences = Preferences(
            hotKey: HotKey(keyCode: 49, modifiers: [.command, .shift]),
            gridColumns: 9,
            gridRows: 6,
            launchAtLogin: false
        )

        try store.save(preferences)

        #expect(store.load() == preferences)
    }

    @Test(arguments: ["not json", #"{ "schemaVersion" : 2, "preferences" : { } }"#])
    func storeIgnoresAnUnreadableValue(storedValue: String) {
        let storage = InMemoryStorage()
        storage.set(storedValue, forKey: "preferences")

        #expect(PreferencesStore(storage: storage).load() == nil)
    }

    @Test func aGlobalShortcutNeedsCommandOptionOrControlUnlessItIsAFunctionKey() {
        let s: UInt16 = 0x01
        let f5: UInt16 = 0x60

        #expect(HotKey(keyCode: s, modifiers: [.option]).isUsableAsGlobalShortcut)
        #expect(HotKey(keyCode: s, modifiers: [.command, .shift]).isUsableAsGlobalShortcut)
        #expect(HotKey(keyCode: s, modifiers: [.control]).isUsableAsGlobalShortcut)
        #expect(!HotKey(keyCode: s, modifiers: []).isUsableAsGlobalShortcut)
        #expect(!HotKey(keyCode: s, modifiers: [.shift]).isUsableAsGlobalShortcut)
        #expect(HotKey(keyCode: f5, modifiers: []).isUsableAsGlobalShortcut)
    }
}
