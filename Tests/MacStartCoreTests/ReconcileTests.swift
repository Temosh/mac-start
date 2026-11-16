import MacStartCore
import Testing

@Suite("Reconcile")
struct ReconcileTests {
    let books = appID("Books")
    let mail = appID("Mail")
    let maps = appID("Maps")
    let notes = appID("Notes")
    let capacity = 35

    @Test func emptyCatalogGivesOneEmptyPage() {
        let result = Layout.empty.reconciled(with: .empty, pageCapacity: capacity)
        #expect(result == Layout(pages: [Page()], hidden: []))
    }

    @Test func firstReconcilePlacesEveryAppByName() {
        let result = Layout.empty.reconciled(with: catalog(notes, mail, maps), pageCapacity: capacity)
        #expect(result.pages == [Page(items: [.app(mail), .app(maps), .app(notes)])])
    }

    @Test func keepsTheFirstOccurrenceOfDuplicatesInReadingOrder() {
        let group = Folder(name: "Group", apps: [notes, mail, maps])
        let layout = Layout(pages: [
            Page(items: [.app(mail), .folder(group)]),
            Page(items: [.app(notes), .app(maps)]),
        ])

        let result = layout.reconciled(with: catalog(mail, notes, maps), pageCapacity: capacity)

        let expectedGroup = Folder(id: group.id, name: "Group", apps: [notes, maps])
        #expect(result.pages == [Page(items: [.app(mail), .folder(expectedGroup)])])
    }

    @Test func hiddenWinsOverPlacement() {
        let layout = Layout(pages: [Page(items: [.app(mail), .app(notes)])], hidden: [mail])

        let result = layout.reconciled(with: catalog(mail, notes), pageCapacity: capacity)

        #expect(result.pages == [Page(items: [.app(notes)])])
        #expect(result.hidden == [mail])
    }

    @Test func removesUninstalledPlacedApps() {
        let layout = Layout(pages: [Page(items: [.app(mail), .app(notes)])])

        let result = layout.reconciled(with: catalog(notes), pageCapacity: capacity)

        #expect(result.pages == [Page(items: [.app(notes)])])
    }

    @Test func keepsUninstalledHiddenAppsSoAReinstallStaysHidden() {
        let layout = Layout(pages: [Page(items: [.app(notes)])], hidden: [maps])

        let uninstalled = layout.reconciled(with: catalog(notes), pageCapacity: capacity)
        let reinstalled = uninstalled.reconciled(with: catalog(notes, maps), pageCapacity: capacity)

        #expect(uninstalled.hidden == [maps])
        #expect(reinstalled.hidden == [maps])
        #expect(reinstalled.pages == [Page(items: [.app(notes)])])
    }

    @Test func rebindsAMovedAppInItsSlot() {
        let movedMail = appID("Mail", in: "/Applications/Utilities")
        let layout = Layout(pages: [Page(items: [.app(notes), .app(mail), .app(maps)])])

        let result = layout.reconciled(with: catalog(notes, movedMail, maps), pageCapacity: capacity)

        #expect(result.pages == [Page(items: [.app(notes), .app(movedMail), .app(maps)])])
    }

    @Test func rebindsAMovedHiddenApp() {
        let movedMaps = appID("Maps", in: "/Applications/Utilities")
        let layout = Layout(pages: [Page(items: [.app(notes)])], hidden: [maps])

        let result = layout.reconciled(with: catalog(notes, movedMaps), pageCapacity: capacity)

        #expect(result.hidden == [movedMaps])
        #expect(result.pages == [Page(items: [.app(notes)])])
    }

    @Test func doesNotRebindWhenSeveralUnmatchedAppsShareTheBundleIdentifier() {
        let stored = AppID(path: "/Applications/Old/Tool.app", bundleIdentifier: "test.tool")
        let release = AppID(path: "/Applications/Tool.app", bundleIdentifier: "test.tool")
        let beta = AppID(path: "/Applications/Tool Beta.app", bundleIdentifier: "test.tool")
        let layout = Layout(pages: [Page(items: [.app(stored)])])

        let result = layout.reconciled(with: Catalog([app(release), app(beta)]), pageCapacity: capacity)

        #expect(result.pages == [Page(items: [.app(release), .app(beta)])])
    }

    @Test func rebindsToTheOneUnmatchedAppWhenTheOtherBundleIsMatchedByPath() {
        let stored = AppID(path: "/Applications/Old/Tool.app", bundleIdentifier: "test.tool")
        let release = AppID(path: "/Applications/Tool.app", bundleIdentifier: "test.tool")
        let beta = AppID(path: "/Applications/Tool Beta.app", bundleIdentifier: "test.tool")
        let layout = Layout(pages: [Page(items: [.app(beta), .app(stored)])])

        let result = layout.reconciled(with: Catalog([app(release), app(beta)]), pageCapacity: capacity)

        #expect(result.pages == [Page(items: [.app(beta), .app(release)])])
    }

    @Test func aPlacedEntryRebindsBeforeAHiddenOne() {
        let placed = AppID(path: "/Applications/Old/Tool.app", bundleIdentifier: "test.tool")
        let hidden = AppID(path: "/Applications/Older/Tool.app", bundleIdentifier: "test.tool")
        let current = AppID(path: "/Applications/Tool.app", bundleIdentifier: "test.tool")
        let layout = Layout(pages: [Page(items: [.app(placed)])], hidden: [hidden])

        let result = layout.reconciled(with: Catalog([app(current)]), pageCapacity: capacity)

        #expect(result.pages == [Page(items: [.app(current)])])
        #expect(result.hidden == [hidden])
    }

    @Test func takesTheCatalogsBundleIdentifierForAnAppAtTheSamePath() {
        let stored = AppID(path: "/Applications/Mail.app", bundleIdentifier: "test.old")
        let current = AppID(path: "/Applications/Mail.app", bundleIdentifier: "test.new")
        let layout = Layout(pages: [Page(items: [.app(stored)])])

        let result = layout.reconciled(with: Catalog([app(current)]), pageCapacity: capacity)

        #expect(result.placedAppIDs.map(\.bundleIdentifier) == ["test.new"])
    }

    @Test func appendsNewAppsToTheLastPageByName() {
        let layout = Layout(pages: [Page(items: [.app(mail)]), Page(items: [.app(notes)])])

        let result = layout.reconciled(with: catalog(mail, notes, maps, books), pageCapacity: capacity)

        #expect(result.pages == [Page(items: [.app(mail)]), Page(items: [.app(notes), .app(books), .app(maps)])])
    }

    @Test func dissolvesAFolderWithOneAppIntoTheSameSlot() {
        let group = Folder(name: "Group", apps: [mail, maps])
        let layout = Layout(pages: [Page(items: [.app(notes), .folder(group), .app(books)])])

        let result = layout.reconciled(with: catalog(notes, mail, books), pageCapacity: capacity)

        #expect(result.pages == [Page(items: [.app(notes), .app(mail), .app(books)])])
    }

    @Test func removesAFolderWithoutApps() {
        let group = Folder(name: "Group", apps: [mail, maps])
        let layout = Layout(pages: [Page(items: [.app(notes), .folder(group)])])

        let result = layout.reconciled(with: catalog(notes), pageCapacity: capacity)

        #expect(result.pages == [Page(items: [.app(notes)])])
    }

    @Test func removesEmptyPages() {
        let layout = Layout(pages: [
            Page(items: [.app(mail)]), Page(), Page(items: [.app(maps)]), Page(items: [.app(notes)]),
        ])

        let result = layout.reconciled(with: catalog(mail, notes), pageCapacity: capacity)

        #expect(result.pages == [Page(items: [.app(mail)]), Page(items: [.app(notes)])])
    }

    @Test func movesOverflowOntoTheNextPageInOrder() {
        let layout = Layout(pages: [Page(items: [.app(books), .app(mail), .app(maps)]), Page(items: [.app(notes)])])

        let result = layout.reconciled(with: catalog(books, mail, maps, notes), pageCapacity: 2)

        #expect(result.pages == [Page(items: [.app(books), .app(mail)]), Page(items: [.app(maps), .app(notes)])])
    }

    @Test func shrinkingTheGridCascadesAcrossEveryPage() {
        let apps = (1...6).map { appID("App\($0)") }
        let layout = Layout(pages: [
            Page(items: apps[0..<3].map(Item.app)),
            Page(items: apps[3..<6].map(Item.app)),
        ])

        let result = layout.reconciled(with: Catalog(apps.map { app($0) }), pageCapacity: 2)

        #expect(result.pages == stride(from: 0, to: 6, by: 2).map { Page(items: apps[$0..<$0 + 2].map(Item.app)) })
    }

    @Test func reconcilingTwiceChangesNothing() {
        let group = Folder(name: "Group", apps: [mail, maps, notes])
        let layout = Layout(pages: [Page(items: [.folder(group), .app(mail)])], hidden: [books])
        let installed = catalog(books, mail, maps, notes, appID("Photos"))

        let once = layout.reconciled(with: installed, pageCapacity: 2)

        #expect(once.reconciled(with: installed, pageCapacity: 2) == once)
        #expect(once.invariantViolations(catalog: installed, pageCapacity: 2).isEmpty)
    }
}
