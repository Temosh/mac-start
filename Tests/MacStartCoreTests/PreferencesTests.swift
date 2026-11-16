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

    @Test func gridSizeStaysWithinTheAllowedRanges() {
        var preferences = Preferences(hotKey: .default, gridColumns: 99, gridRows: 0, launchAtLogin: true)
        #expect(preferences.gridColumns == Preferences.allowedGridColumns.upperBound)
        #expect(preferences.gridRows == Preferences.allowedGridRows.lowerBound)

        preferences.gridColumns = 1
        preferences.gridRows = 50
        #expect(preferences.gridColumns == Preferences.allowedGridColumns.lowerBound)
        #expect(preferences.gridRows == Preferences.allowedGridRows.upperBound)
    }

    @Test func storeLoadsNilBeforeTheFirstSave() {
        #expect(PreferencesStore(storage: InMemoryStorage()).load() == nil)
    }

    @Test func storeKeepsSavedPreferences() throws {
        let store = PreferencesStore(storage: InMemoryStorage())
        let preferences = Preferences(
            hotKey: HotKey(keyCode: 49, modifiers: [.command, .shift]),
            gridColumns: 9,
            gridRows: 4,
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
