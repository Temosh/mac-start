import Foundation
import MacStartCore
import Testing

@Suite("Catalog change filter")
struct CatalogChangeFilterTests {
    private let filter = CatalogChangeFilter(roots: [
        URL(filePath: "/Applications", directoryHint: .isDirectory),
        URL(filePath: "/Users/test/Applications", directoryHint: .isDirectory),
    ])

    @Test(arguments: [
        "/Applications/",
        "/Applications/Utilities",
        // Four levels down: the entries of this folder are five levels down, where the scan still finds apps.
        "/Applications/Unity/Hub/Editor/6000.1/",
        "/Applications/Safari.app/",
        "/Applications/Xcode.app/Contents/",
        "/Applications/Unity/Hub/Editor/6000.1/Unity.app/Contents/",
        "/Users/test/Applications/",
        "/Volumes/Backup/",
    ])
    func countsChangesThatCanAddRemoveOrUpdateAnApp(path: String) {
        #expect(filter.canChangeCatalog(path: path))
    }

    @Test(arguments: [
        "/Applications/Xcode.app/Contents/Developer/Platforms/",
        "/Applications/Safari.app/Contents/Resources/",
        // Five levels down: the entries of this folder are deeper than the scan looks.
        "/Applications/Unity/Hub/Editor/6000.1/PlaybackEngines/",
        "/Applications/Unity/Hub/Editor/6000.1/PlaybackEngines/AndroidPlayer/SDK/",
        "/Applications/A/B/C/D/E/Deep.app/Contents/",
        "/Applications/.Downloading.app/Contents/",
        "/Users/test/Applications/.cache/",
    ])
    func ignoresChangesInsideBundlesDotFoldersOrBelowTheScanDepth(path: String) {
        #expect(!filter.canChangeCatalog(path: path))
    }

    @Test func judgesTheRealPathsOfARootReachedThroughASymbolicLink() throws {
        try withTemporaryDirectory { directory in
            let target = directory.appending(path: "Target", directoryHint: .isDirectory)
            let link = directory.appending(path: "Linked", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            // The temporary directory itself is under `/var`, a link to `/private/var`, as FSEvents names it.
            let realTarget = try #require(realpath(target.path(percentEncoded: false), nil))
            defer { free(realTarget) }
            let reported = String(cString: realTarget)

            let filter = CatalogChangeFilter(roots: [link])

            #expect(filter.canChangeCatalog(path: reported + "/"))
            #expect(!filter.canChangeCatalog(path: reported + "/Tool.app/Contents/Resources/"))
        }
    }
}
