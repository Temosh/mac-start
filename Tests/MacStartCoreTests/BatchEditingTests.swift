import Foundation
import MacStartCore
import Testing

@Suite("Batch editing")
struct BatchEditingTests {
    let a = appID("A")
    let b = appID("B")
    let c = appID("C")
    let d = appID("D")
    let capacity = 35

    private func ids(_ items: Item...) -> Set<Item.ID> {
        Set(items.map(\.id))
    }

    // MARK: - Move to page

    @Test func movesItemsToTheEndOfAPageInReadingOrder() {
        var layout = Layout(pages: [Page(items: [.app(a), .app(b)]), Page(items: [.app(c), .app(d)])])

        layout.moveItems(ids(.app(c), .app(a)), toPage: 1, pageCapacity: capacity)

        #expect(layout.pages == [Page(items: [.app(b)]), Page(items: [.app(d), .app(a), .app(c)])])
    }

    @Test func aPageOnePastTheLastAddsAPage() {
        var layout = Layout(pages: [Page(items: [.app(a), .app(b), .app(c)])])

        layout.moveItems(ids(.app(b)), toPage: 1, pageCapacity: capacity)

        #expect(layout.pages == [Page(items: [.app(a), .app(c)]), Page(items: [.app(b)])])
    }

    @Test func movesAWholeFolder() {
        let folder = Folder(name: "Pair", apps: [a, b])
        var layout = Layout(pages: [Page(items: [.folder(folder), .app(c)]), Page(items: [.app(d)])])

        layout.moveItems(ids(.folder(folder)), toPage: 1, pageCapacity: capacity)

        #expect(layout.pages == [Page(items: [.app(c)]), Page(items: [.app(d), .folder(folder)])])
    }

    @Test func anAppMovedOutOfAFolderLeavesItAndAFolderWithOneAppDissolves() {
        let folder = Folder(name: "Pair", apps: [a, b])
        var layout = Layout(pages: [Page(items: [.folder(folder), .app(c)])])

        layout.moveItems(ids(.app(a)), toPage: 1, pageCapacity: capacity)

        #expect(layout.pages == [Page(items: [.app(b), .app(c)]), Page(items: [.app(a)])])
    }

    @Test func movingMoreItemsThanAPageHasRoomForIsRefused() {
        let original = Layout(pages: [Page(items: [.app(a)]), Page(items: [.app(b), .app(c)])])
        var layout = original

        let isMoved = layout.moveItems(ids(.app(b), .app(c)), toPage: 0, pageCapacity: 2)

        #expect(!isMoved)
        #expect(layout == original)
        #expect(!original.canMoveItems(ids(.app(b), .app(c)), toPage: 0, pageCapacity: 2))
        #expect(original.canMoveItems(ids(.app(b)), toPage: 0, pageCapacity: 2))
    }

    @Test func anEmptiedPageGoesAway() {
        var layout = Layout(pages: [Page(items: [.app(a)]), Page(items: [.app(b)])])

        let isMoved = layout.moveItems(ids(.app(b)), toPage: 0, pageCapacity: 2)

        #expect(isMoved)
        #expect(layout.pages == [Page(items: [.app(a), .app(b)])])
    }

    @Test func aNewPageTakesAsManyPagesAsTheItemsFill() {
        var layout = Layout(pages: [Page(items: [.app(a), .app(b)]), Page(items: [.app(c), .app(d)])])

        let isMoved = layout.moveItems(ids(.app(a), .app(b), .app(c)), toPage: 2, pageCapacity: 2)

        #expect(isMoved)
        #expect(
            layout.pages == [Page(items: [.app(d)]), Page(items: [.app(a), .app(b)]), Page(items: [.app(c)])]
        )
    }

    @Test func unknownItemsChangeNothing() {
        let original = Layout(pages: [Page(items: [.app(a), .app(b)])])
        var layout = original

        layout.moveItems(ids(.app(d)), toPage: 0, pageCapacity: capacity)

        #expect(layout == original)
    }

    // MARK: - Remove from folder

    @Test func removesAppsFromAFolderIntoTheSlotsAfterItInFolderOrder() {
        let folder = Folder(name: "Four", apps: [a, b, c, d])
        let e = appID("E")
        var layout = Layout(pages: [Page(items: [.folder(folder), .app(e)])])

        layout.removeApps([d, b], fromFolder: folder.id, pageCapacity: capacity)

        let rest = Folder(id: folder.id, name: "Four", apps: [a, c])
        #expect(layout.pages == [Page(items: [.folder(rest), .app(b), .app(d), .app(e)])])
    }

    @Test func aFolderLeftWithOneAppDissolvesWhenAppsLeaveIt() {
        let folder = Folder(name: "Three", apps: [a, b, c])
        var layout = Layout(pages: [Page(items: [.folder(folder), .app(d)])])

        layout.removeApps([a, c], fromFolder: folder.id, pageCapacity: capacity)

        #expect(layout.pages == [Page(items: [.app(b), .app(a), .app(c), .app(d)])])
    }

    @Test func appsOutsideTheFolderStay() {
        let folder = Folder(name: "Three", apps: [a, b, c])
        var layout = Layout(pages: [Page(items: [.folder(folder), .app(d)])])

        let isRemoved = layout.removeApps([a, d], fromFolder: folder.id, pageCapacity: capacity)

        let rest = Folder(id: folder.id, name: "Three", apps: [b, c])
        #expect(isRemoved)
        #expect(layout.pages == [Page(items: [.folder(rest), .app(a), .app(d)])])
    }

    @Test func removingAppsFromAFolderOnAFullPageIsRefused() {
        let folder = Folder(name: "Three", apps: [a, b, c])
        let original = Layout(pages: [Page(items: [.folder(folder), .app(d)])])
        var layout = original

        let isRemoved = layout.removeApps([a], fromFolder: folder.id, pageCapacity: 2)

        #expect(!isRemoved)
        #expect(layout == original)
        #expect(!original.canRemoveApps([a], fromFolder: folder.id, pageCapacity: 2))
    }

    // MARK: - New folder

    @Test func makesAFolderInTheSlotOfTheFirstAppInReadingOrder() throws {
        var layout = Layout(pages: [Page(items: [.app(a), .app(b), .app(c), .app(d)])])
        var namedApps: [AppID] = []

        let id = layout.makeFolder(
            of: [c, a],
            named: { apps in
                namedApps = apps
                return "New"
            },
            pageCapacity: capacity
        )

        let folder = Folder(id: try #require(id), name: "New", apps: [a, c])
        #expect(layout.pages == [Page(items: [.folder(folder), .app(b), .app(d)])])
        #expect(namedApps == [a, c])
    }

    @Test func gathersAppsFromSeveralPages() throws {
        var layout = Layout(pages: [Page(items: [.app(a), .app(b)]), Page(items: [.app(c)])])

        let id = layout.makeFolder(of: [a, c], named: { _ in "New" }, pageCapacity: capacity)

        let folder = Folder(id: try #require(id), name: "New", apps: [a, c])
        #expect(layout.pages == [Page(items: [.folder(folder), .app(b)])])
    }

    @Test func aFirstAppInsideAFolderPutsTheNewFolderRightAfterThatFolder() throws {
        let existing = Folder(name: "Old", apps: [a, b, c])
        var layout = Layout(pages: [Page(items: [.folder(existing), .app(d)])])

        let id = layout.makeFolder(of: [b, d], named: { _ in "New" }, pageCapacity: capacity)

        let rest = Folder(id: existing.id, name: "Old", apps: [a, c])
        let folder = Folder(id: try #require(id), name: "New", apps: [b, d])
        #expect(layout.pages == [Page(items: [.folder(rest), .folder(folder)])])
    }

    @Test func aFolderLeftWithOneAppDissolves() throws {
        let existing = Folder(name: "Old", apps: [a, b])
        var layout = Layout(pages: [Page(items: [.folder(existing), .app(c)])])

        let id = layout.makeFolder(of: [a, c], named: { _ in "New" }, pageCapacity: capacity)

        let folder = Folder(id: try #require(id), name: "New", apps: [a, c])
        #expect(layout.pages == [Page(items: [.app(b), .folder(folder)])])
    }

    @Test func aNewFolderInAnAppsSlotFitsAFullPage() throws {
        var layout = Layout(pages: [Page(items: [.app(a), .app(b)])])

        let id = layout.makeFolder(of: [a, b], named: { _ in "New" }, pageCapacity: 2)

        let folder = Folder(id: try #require(id), name: "New", apps: [a, b])
        #expect(layout.pages == [Page(items: [.folder(folder)])])
    }

    @Test func aNewFolderThatDoesNotFitItsPageIsRefused() {
        let existing = Folder(name: "Old", apps: [a, b, c])
        let original = Layout(pages: [Page(items: [.folder(existing), .app(d)])])
        var layout = original

        let id = layout.makeFolder(of: [a, b], named: { _ in "New" }, pageCapacity: 2)

        #expect(id == nil)
        #expect(layout == original)
        #expect(!original.canMakeFolder(of: [a, b], pageCapacity: 2))
    }

    @Test func fewerThanTwoPlacedAppsMakeNoFolder() {
        let original = Layout(pages: [Page(items: [.app(a), .app(b)])])
        var layout = original

        let id = layout.makeFolder(of: [a, d], named: { _ in "New" }, pageCapacity: capacity)

        #expect(id == nil)
        #expect(layout == original)
    }

    @Test func namesAFolderOfSeveralAppsAfterTheFirstCategory() {
        let plain = InstalledApp(id: appID("Plain"), displayName: "Plain")
        let game = InstalledApp(id: appID("Game"), displayName: "Game", categoryIdentifier: "public.app-category.games")
        let utility = InstalledApp(
            id: appID("Utility"),
            displayName: "Utility",
            categoryIdentifier: "public.app-category.utilities"
        )

        #expect(Folder.defaultName(for: [plain, game, utility]) == "Games")
        #expect(Folder.defaultName(for: [plain, plain]) == "Folder")
    }
}
