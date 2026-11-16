import Foundation
import MacStartCore
import Testing

@Suite("Layout file store")
struct LayoutFileStoreTests {
    let layout = Layout(
        pages: [
            Page(items: [.app(appID("Mail")), .folder(Folder(name: "Group", apps: [appID("Maps"), appID("Notes")]))])
        ],
        hidden: [appID("Books")]
    )

    @Test func loadsNilBeforeTheFirstSave() throws {
        try withTemporaryDirectory { directory in
            let store = LayoutFileStore(fileURL: directory.appending(path: "MacStart/layout.json"))

            let loaded = try store.load()

            #expect(loaded == nil)
        }
    }

    @Test func saveCreatesTheFolderAndLoadReturnsTheLayout() throws {
        try withTemporaryDirectory { directory in
            let store = LayoutFileStore(fileURL: directory.appending(path: "MacStart/layout.json"))

            try store.save(layout)

            #expect(try store.load() == layout)
        }
    }

    @Test func saveReplacesThePreviousLayout() throws {
        try withTemporaryDirectory { directory in
            let store = LayoutFileStore(fileURL: directory.appending(path: "layout.json"))

            try store.save(layout)
            try store.save(.empty)

            #expect(try store.load() == .empty)
        }
    }

    @Test func readsAVersion1File() throws {
        try withTemporaryDirectory { directory in
            let fileURL = directory.appending(path: "layout.json")
            try Data(Fixtures.layoutV1.utf8).write(to: fileURL)

            #expect(try LayoutFileStore(fileURL: fileURL).load() == Fixtures.layoutV1Content)
        }
    }

    @Test func reportsAnUnreadableFile() throws {
        try withTemporaryDirectory { directory in
            let fileURL = directory.appending(path: "layout.json")
            try Data("{ \"schemaVersion\" : 1, \"layout\" : 7 }".utf8).write(to: fileURL)

            #expect(throws: PersistenceError.self) { try LayoutFileStore(fileURL: fileURL).load() }
        }
    }

    @Test func movesAnUnreadableFileAside() throws {
        try withTemporaryDirectory { directory in
            let fileURL = directory.appending(path: "layout.json")
            try Data("not a layout".utf8).write(to: fileURL)
            let store = LayoutFileStore(fileURL: fileURL)

            let moved = try store.moveUnreadableFileAside(at: Date(timeIntervalSince1970: 1_794_830_400))

            #expect(moved.lastPathComponent == "layout.unreadable-20261116T120000Z.json")
            #expect(try String(contentsOf: moved, encoding: .utf8) == "not a layout")
            let loaded = try store.load()
            #expect(loaded == nil)
        }
    }

    @Test func standardFileIsInApplicationSupport() {
        #expect(
            LayoutFileStore.standardFileURL.path(percentEncoded: false).hasSuffix(
                "/Library/Application Support/MacStart/layout.json"))
    }
}
