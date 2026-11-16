import Foundation
import MacStartCore
import Testing

@Suite("Catalog scanner")
struct CatalogScannerTests {
    @Test func findsAppsInSubfoldersButNotInsideBundles() throws {
        try withTemporaryDirectory { root in
            try makeAppBundle(at: root.appending(path: "Alpha.app"), bundleIdentifier: "test.alpha", version: "1.0")
            try makeAppBundle(at: root.appending(path: "Tools/Beta.app"), bundleIdentifier: "test.beta", version: "2.1")
            try makeAppBundle(
                at: root.appending(path: "Alpha.app/Contents/Helpers/Helper.app"), bundleIdentifier: "test.helper")
            try makeAppBundle(at: root.appending(path: ".Secret.app"), bundleIdentifier: "test.secret")
            try FileManager.default.createDirectory(at: root.appending(path: "Docs"), withIntermediateDirectories: true)

            let catalog = CatalogScanner(roots: [root]).scan()

            #expect(Set(catalog.apps.map(\.id.path)) == paths(root, "Alpha.app", "Tools/Beta.app"))
            let alpha = try #require(catalog.apps.first { $0.id.bundleIdentifier == "test.alpha" })
            #expect(alpha.displayName == "Alpha")
            #expect(alpha.version == "1.0")
        }
    }

    @Test func includesAnAppWithTheHiddenFileFlagButSkipsDotFolders() throws {
        try withTemporaryDirectory { root in
            var flaggedApp = root.appending(path: "Flagged.app")
            try makeAppBundle(at: flaggedApp, bundleIdentifier: "test.flagged")
            var hiddenFlag = URLResourceValues()
            hiddenFlag.isHidden = true
            try flaggedApp.setResourceValues(hiddenFlag)
            try makeAppBundle(at: root.appending(path: ".cache/Cached.app"), bundleIdentifier: "test.cached")
            try makeAppBundle(at: root.appending(path: "Vendor/Tool.app"), bundleIdentifier: "test.tool")
            try Data().write(to: root.appending(path: "Vendor/.DS_Store"))

            let catalog = CatalogScanner(roots: [root]).scan()

            #expect(Set(catalog.apps.map(\.id.path)) == paths(root, "Flagged.app", "Vendor/Tool.app"))
        }
    }

    @Test func skipsBundlesWithoutInfoPlist() throws {
        try withTemporaryDirectory { root in
            try makeAppBundle(at: root.appending(path: "Real.app"), bundleIdentifier: "test.real")
            try FileManager.default.createDirectory(
                at: root.appending(path: "Templates/Player.app/Contents/MacOS"),
                withIntermediateDirectories: true
            )

            let catalog = CatalogScanner(roots: [root]).scan()

            #expect(Set(catalog.apps.map(\.id.path)) == paths(root, "Real.app"))
        }
    }

    @Test func keepsAnAppWithoutBundleIdentifier() throws {
        try withTemporaryDirectory { root in
            try makeAppBundle(at: root.appending(path: "Plain.app"), bundleIdentifier: nil)

            let app = try #require(CatalogScanner(roots: [root]).scan().apps.first)

            #expect(app.id.bundleIdentifier == nil)
            #expect(app.displayName == "Plain")
        }
    }

    @Test func includesASymbolicLinkToAnAppOutsideTheRoots() throws {
        try withTemporaryDirectory { directory in
            let root = directory.appending(path: "Applications")
            let target = directory.appending(path: "Elsewhere/Viewer.app")
            try makeAppBundle(at: target, bundleIdentifier: "test.viewer")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "Viewer.app"), withDestinationURL: target)

            let app = try #require(CatalogScanner(roots: [root]).scan().apps.first)

            #expect(app.id.path == root.appending(path: "Viewer.app").path(percentEncoded: false))
            #expect(app.id.bundleIdentifier == "test.viewer")
            #expect(trimmedPath(app.bundleURL) == trimmedPath(target.resolvingSymlinksInPath()))
        }
    }

    @Test func keepsALinkAndItsTargetInsideTheRootsOnceUnderTheTargetPath() throws {
        try withTemporaryDirectory { root in
            let target = root.appending(path: "Vendor/Tool.app")
            try makeAppBundle(at: target, bundleIdentifier: "test.tool")
            try FileManager.default.createSymbolicLink(at: root.appending(path: "Tool.app"), withDestinationURL: target)

            let catalog = CatalogScanner(roots: [root]).scan()

            #expect(Set(catalog.apps.map(\.id.path)) == paths(root, "Vendor/Tool.app"))
        }
    }

    @Test func keepsTwoBundlesWithOneBundleIdentifierAsTwoApps() throws {
        try withTemporaryDirectory { root in
            try makeAppBundle(at: root.appending(path: "Tool.app"), bundleIdentifier: "test.tool", version: "1.0")
            try makeAppBundle(at: root.appending(path: "Beta/Tool.app"), bundleIdentifier: "test.tool", version: "2.0")

            let catalog = CatalogScanner(roots: [root]).scan()

            #expect(Set(catalog.apps.map(\.id.path)) == paths(root, "Tool.app", "Beta/Tool.app"))
            #expect(Set(catalog.apps.compactMap(\.version)) == ["1.0", "2.0"])
        }
    }

    @Test func readsAWrappedIOSApp() throws {
        try withTemporaryDirectory { root in
            let wrapper = root.appending(path: "Game.app")
            let inner = wrapper.appending(path: "Wrapper/Game.app")
            try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
            let info = try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": "test.game"],
                format: .xml,
                options: 0
            )
            try info.write(to: inner.appending(path: "Info.plist"))
            try FileManager.default.createSymbolicLink(
                atPath: wrapper.appending(path: "WrappedBundle").path(percentEncoded: false),
                withDestinationPath: "Wrapper/Game.app"
            )

            let app = try #require(CatalogScanner(roots: [root]).scan().apps.first)

            #expect(app.id.bundleIdentifier == "test.game")
        }
    }

    @Test func skipsMissingRoots() throws {
        try withTemporaryDirectory { root in
            try makeAppBundle(at: root.appending(path: "Alpha.app"), bundleIdentifier: "test.alpha")

            let catalog = CatalogScanner(roots: [root.appending(path: "Missing"), root]).scan()

            #expect(Set(catalog.apps.map(\.id.path)) == paths(root, "Alpha.app"))
        }
    }

    @Test func standardRootsAreTheThreeAppFolders() {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)

        let roots = CatalogScanner.standardRoots(homeDirectory: home).map { $0.path(percentEncoded: false) }

        #expect(roots == ["/Applications/", "/System/Applications/", "/Users/someone/Applications/"])
    }

    /// The URL's path without a trailing slash. Directory URLs may or may not end in one.
    private func trimmedPath(_ url: URL) -> String {
        AppID(path: url.path(percentEncoded: false), bundleIdentifier: nil).path
    }

    /// Standardized paths of the given entries under `root`.
    private func paths(_ root: URL, _ relativePaths: String...) -> Set<String> {
        Set(
            relativePaths.map {
                AppID(path: root.appending(path: $0).path(percentEncoded: false), bundleIdentifier: nil).path
            })
    }
}
