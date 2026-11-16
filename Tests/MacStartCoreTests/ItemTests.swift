import Foundation
import MacStartCore
import Testing

@Suite("Item")
struct ItemTests {
    @Test func appItemIDDependsOnlyOnThePath() {
        let withIdentifier = Item.app(appID("Mail"))
        let withoutIdentifier = Item.app(AppID(path: "/Applications/Mail.app", bundleIdentifier: nil))

        #expect(withIdentifier.id == withoutIdentifier.id)
        #expect(withIdentifier.id != Item.app(appID("Notes")).id)
    }

    @Test func folderItemIDSurvivesRenamesAndContentChanges() {
        let folder = Folder(name: "Work", apps: [appID("Mail"), appID("Notes")])
        let changed = Folder(id: folder.id, name: "Office", apps: [appID("Maps")])

        #expect(Item.folder(folder).id == Item.folder(changed).id)
        #expect(Item.folder(folder).id != Item.app(appID("Mail")).id)
    }
}
