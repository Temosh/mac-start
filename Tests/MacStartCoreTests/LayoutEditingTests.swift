import Foundation
import MacStartCore
import Testing

@Suite("Layout editing")
struct LayoutEditingTests {
    let a = appID("A")
    let b = appID("B")
    let c = appID("C")
    let d = appID("D")
    let capacity = 35

    private func slot(_ page: Int, _ slot: Int) -> LayoutLocation {
        .slot(GridPosition(page: page, slot: slot))
    }

    @Test func movesAnItemForwardWithinAPage() {
        var layout = Layout(pages: [Page(items: [.app(a), .app(b), .app(c), .app(d)])])

        layout.moveItem(from: slot(0, 0), to: GridPosition(page: 0, slot: 2), pageCapacity: capacity)

        #expect(layout.pages == [Page(items: [.app(b), .app(c), .app(a), .app(d)])])
    }

    @Test func movesAnItemBackwardWithinAPage() {
        var layout = Layout(pages: [Page(items: [.app(a), .app(b), .app(c), .app(d)])])

        layout.moveItem(from: slot(0, 3), to: GridPosition(page: 0, slot: 0), pageCapacity: capacity)

        #expect(layout.pages == [Page(items: [.app(d), .app(a), .app(b), .app(c)])])
    }

    @Test func movesAnItemToAnotherPageAndRemovesTheEmptiedPage() {
        var layout = Layout(pages: [Page(items: [.app(a)]), Page(items: [.app(b), .app(c)])])

        layout.moveItem(from: slot(0, 0), to: GridPosition(page: 1, slot: 1), pageCapacity: capacity)

        #expect(layout.pages == [Page(items: [.app(b), .app(a), .app(c)])])
    }

    @Test func movingOntoAFullPagePushesItsLastItemToTheNextPage() {
        var layout = Layout(pages: [Page(items: [.app(a), .app(b)]), Page(items: [.app(c)])])

        layout.moveItem(from: slot(1, 0), to: GridPosition(page: 0, slot: 0), pageCapacity: 2)

        #expect(layout.pages == [Page(items: [.app(c), .app(a)]), Page(items: [.app(b)])])
    }

    @Test func aDestinationPastTheLastPageAddsAPage() {
        var layout = Layout(pages: [Page(items: [.app(a), .app(b)])])

        layout.moveItem(from: slot(0, 0), to: GridPosition(page: 1, slot: 0), pageCapacity: capacity)

        #expect(layout.pages == [Page(items: [.app(b)]), Page(items: [.app(a)])])
    }

    @Test func movesAnAppOutOfAFolderAndDissolvesAFolderLeftWithOneApp() {
        let folder = Folder(name: "Pair", apps: [a, b])
        var layout = Layout(pages: [Page(items: [.folder(folder), .app(c)])])

        layout.moveItem(
            from: .inFolder(folder.id, index: 1), to: GridPosition(page: 0, slot: 2), pageCapacity: capacity)

        #expect(layout.pages == [Page(items: [.app(a), .app(c), .app(b)])])
    }

    @Test func dropsAnAppOntoAnAppToMakeAFolderInTheTargetsSlot() throws {
        var layout = Layout(pages: [Page(items: [.app(a), .app(b), .app(c)])])

        let dropped = layout.dropApp(
            from: slot(0, 2), onto: GridPosition(page: 0, slot: 0), newFolderName: { _, _ in "Tools" },
            pageCapacity: capacity)
        let folderID = try #require(dropped)

        let folder = Folder(id: folderID, name: "Tools", apps: [a, c])
        #expect(layout.pages == [Page(items: [.folder(folder), .app(b)])])
    }

    @Test func targetSlotsCountWithoutTheDraggedItem() throws {
        var layout = Layout(pages: [Page(items: [.app(a), .app(b), .app(c)])])

        let dropped = layout.dropApp(
            from: slot(0, 0), onto: GridPosition(page: 0, slot: 1), newFolderName: { _, _ in "Pair" },
            pageCapacity: capacity)
        let folderID = try #require(dropped)

        #expect(layout.pages == [Page(items: [.app(b), .folder(Folder(id: folderID, name: "Pair", apps: [c, a]))])])
    }

    @Test func dropsAnAppOntoAFolderToJoinIt() {
        let folder = Folder(name: "Group", apps: [a, b])
        var layout = Layout(pages: [Page(items: [.folder(folder), .app(c)])])

        let folderID = layout.dropApp(
            from: slot(0, 1),
            onto: GridPosition(page: 0, slot: 0),
            newFolderName: { _, _ in "Unused" },
            pageCapacity: capacity
        )

        #expect(folderID == folder.id)
        #expect(layout.pages == [Page(items: [.folder(Folder(id: folder.id, name: "Group", apps: [a, b, c]))])])
    }

    @Test func aFolderCannotBeDroppedIntoAnother() {
        let first = Folder(name: "First", apps: [a, b])
        let second = Folder(name: "Second", apps: [c, d])
        let original = Layout(pages: [Page(items: [.folder(first), .folder(second)])])
        var layout = original

        let folderID = layout.dropApp(
            from: slot(0, 0),
            onto: GridPosition(page: 0, slot: 0),
            newFolderName: { _, _ in "New" },
            pageCapacity: capacity
        )

        #expect(folderID == nil)
        #expect(layout == original)
    }

    @Test func dropsAnAppFromAFolderOntoAnApp() throws {
        let folder = Folder(name: "Pair", apps: [a, b])
        var layout = Layout(pages: [Page(items: [.folder(folder), .app(c)])])

        let dropped = layout.dropApp(
            from: .inFolder(folder.id, index: 0),
            onto: GridPosition(page: 0, slot: 1),
            newFolderName: { _, _ in "New" },
            pageCapacity: capacity
        )
        let folderID = try #require(dropped)

        #expect(layout.pages == [Page(items: [.app(b), .folder(Folder(id: folderID, name: "New", apps: [c, a]))])])
    }

    @Test func removingAnAppFromAFolderPlacesItRightAfterTheFolder() {
        let folder = Folder(name: "Group", apps: [a, b, c])
        var layout = Layout(pages: [Page(items: [.folder(folder), .app(d)])])

        layout.removeApp(fromFolder: folder.id, at: 0, pageCapacity: capacity)

        let rest = Folder(id: folder.id, name: "Group", apps: [b, c])
        #expect(layout.pages == [Page(items: [.folder(rest), .app(a), .app(d)])])
    }

    @Test func reordersAppsInsideAFolder() {
        let folder = Folder(name: "Group", apps: [a, b, c])
        var layout = Layout(pages: [Page(items: [.folder(folder)])])

        layout.moveApp(inFolder: folder.id, from: 0, to: 2)

        #expect(layout.pages == [Page(items: [.folder(Folder(id: folder.id, name: "Group", apps: [b, c, a]))])])
    }

    @Test func renamesAFolderAndKeepsTheNameForEmptyInput() {
        let folder = Folder(name: "Group", apps: [a, b])
        var layout = Layout(pages: [Page(items: [.folder(folder)])])

        layout.renameFolder(folder.id, to: "  Games ")
        layout.renameFolder(folder.id, to: "   ")

        #expect(layout.pages == [Page(items: [.folder(Folder(id: folder.id, name: "Games", apps: [a, b]))])])
    }

    @Test func invalidPositionsChangeNothing() {
        let original = Layout(pages: [Page(items: [.app(a), .app(b)])])
        var layout = original

        layout.moveItem(from: slot(4, 0), to: GridPosition(page: 0, slot: 0), pageCapacity: capacity)
        let folderID = layout.dropApp(
            from: slot(0, 0),
            onto: GridPosition(page: 0, slot: 9),
            newFolderName: { _, _ in "New" },
            pageCapacity: capacity
        )
        layout.renameFolder(UUID(), to: "Nothing")

        #expect(folderID == nil)
        #expect(layout == original)
    }

    @Test(arguments: [
        ("public.app-category.developer-tools", "Developer Tools"),
        ("public.app-category.utilities", "Utilities"),
        ("public.app-category.social-networking", "Social Networking"),
        ("com.example.custom-category", nil),
        ("public.app-category.", nil),
    ])
    func categoryNamesComeFromTheIdentifier(identifier: String, expected: String?) {
        let app = InstalledApp(id: appID("App"), displayName: "App", categoryIdentifier: identifier)

        #expect(app.categoryName == expected)
    }

    @Test func aNewFolderIsNamedAfterTheTargetsCategoryFirst() {
        let utility = InstalledApp(
            id: appID("Tool"),
            displayName: "Tool",
            categoryIdentifier: "public.app-category.utilities"
        )
        let game = InstalledApp(id: appID("Game"), displayName: "Game", categoryIdentifier: "public.app-category.games")
        let plain = InstalledApp(id: appID("Plain"), displayName: "Plain")

        #expect(Folder.defaultName(target: utility, dropped: game) == "Utilities")
        #expect(Folder.defaultName(target: plain, dropped: game) == "Games")
        #expect(Folder.defaultName(target: plain, dropped: plain) == "Folder")
    }
}
