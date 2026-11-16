import MacStartCore
import Testing

@Suite("Search")
struct SearchTests {
    /// A one-page layout with the given apps, and a catalog that has all of them installed.
    private func placed(_ names: String...) -> (Layout, Catalog) {
        let ids = names.map { appID($0) }
        return (Layout(pages: [Page(items: ids.map(Item.app))]), Catalog(ids.map { app($0) }))
    }

    private func names(_ results: [InstalledApp]) -> [String] {
        results.map(\.displayName)
    }

    @Test func ranksNameStartThenWordStartThenAnywhere() {
        let (layout, catalog) = placed("Notes", "Pages Templates", "Terminal")

        let results = layout.searchResults(matching: "te", in: catalog)

        #expect(names(results) == ["Terminal", "Pages Templates", "Notes"])
    }

    @Test func keepsFinderOrderWithinOneRank() {
        let (layout, catalog) = placed("Maps", "Mail", "Music")

        #expect(names(layout.searchResults(matching: "m", in: catalog)) == ["Mail", "Maps", "Music"])
    }

    @Test func requiresEveryWordOfTheQuery() {
        let (layout, catalog) = placed("Visual Studio Code", "Code Runner", "Studio One")

        #expect(names(layout.searchResults(matching: "stu co", in: catalog)) == ["Visual Studio Code"])
    }

    @Test func ignoresCaseDiacriticsAndPunctuation() {
        let (layout, catalog) = placed("Café Menu", "Calendar")

        #expect(names(layout.searchResults(matching: "CAFE", in: catalog)) == ["Café Menu"])
        #expect(names(layout.searchResults(matching: "café-menu", in: catalog)) == ["Café Menu"])
    }

    @Test func findsAppsInsideFolders() {
        let maps = appID("Maps")
        let layout = Layout(pages: [Page(items: [.folder(Folder(name: "Travel", apps: [maps, appID("Weather")]))])])

        let results = layout.searchResults(matching: "map", in: Catalog([app(maps), app(appID("Weather"))]))

        #expect(names(results) == ["Maps"])
    }

    @Test func neverReturnsHiddenOrUninstalledApps() {
        let notes = appID("Notes")
        let notepad = appID("Notepad")
        let notebook = appID("Notebook")
        let layout = Layout(pages: [Page(items: [.app(notes), .app(notebook)])], hidden: [notepad])

        let results = layout.searchResults(matching: "note", in: Catalog([app(notes), app(notepad)]))

        #expect(names(results) == ["Notes"])
    }

    @Test(arguments: ["", "   ", "-", "  /  "])
    func findsNothingWithoutLettersOrDigits(query: String) {
        let (layout, catalog) = placed("Notes")

        #expect(layout.searchResults(matching: query, in: catalog).isEmpty)
    }
}
