import Foundation
import MacStartCore

/// An app ID for tests: `<folder>/<name>.app` with the bundle identifier `test.<name>` in lowercase.
func appID(_ name: String, in folder: String = "/Applications") -> AppID {
    AppID(path: "\(folder)/\(name).app", bundleIdentifier: "test.\(name.lowercased())")
}

/// A catalog app for `id`, named after its file.
func app(_ id: AppID, version: String? = nil) -> InstalledApp {
    InstalledApp(
        id: id, displayName: URL(filePath: id.path).deletingPathExtension().lastPathComponent, version: version)
}

/// A catalog with one app per ID.
func catalog(_ ids: AppID...) -> Catalog {
    Catalog(ids.map { app($0) })
}

/// Runs `body` with a new, empty directory and deletes the directory afterwards.
///
/// The directory URL is canonical (`/private/var/...`, not `/var/...`), because directory enumeration
/// reports canonical paths.
func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let created = FileManager.default.temporaryDirectory.appending(
        path: "MacStartCoreTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: created) }
    let canonicalPath = try created.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
    try body(URL(filePath: canonicalPath ?? created.path(percentEncoded: false), directoryHint: .isDirectory))
}

/// Creates a minimal app bundle: `Contents/Info.plist` with the given keys.
func makeAppBundle(at url: URL, bundleIdentifier: String?, version: String? = nil, category: String? = nil) throws {
    let contents = url.appending(path: "Contents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    var info = ["CFBundlePackageType": "APPL"]
    info["CFBundleIdentifier"] = bundleIdentifier
    info["CFBundleShortVersionString"] = version
    info["LSApplicationCategoryType"] = category
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: contents.appending(path: "Info.plist"))
}

/// A deterministic random number generator (SplitMix64), so random tests repeat exactly for a seed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// An in-memory `KeyValueStorage`.
final class InMemoryStorage: KeyValueStorage {
    private var values: [String: Any] = [:]

    func string(forKey key: String) -> String? {
        values[key] as? String
    }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }
}
