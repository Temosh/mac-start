import Foundation
import os

/// Finds the installed apps under a set of app folders.
///
/// An app is a `.app` bundle with an `Info.plist`, found up to `maxDepth` levels below a root without looking
/// inside bundles. Names starting with a dot are skipped. A symbolic link to an app counts as that app. When a link
/// and its target are both found, the app is kept once, under the target's path. The scan does file I/O, so run it
/// off the main actor.
public struct CatalogScanner: Sendable {
    /// How many levels below a root apps are found by default. Unity Hub keeps its editors five levels down
    /// (`/Applications/Unity/Hub/Editor/<version>/Unity.app`). Deeper folders hold content such as SDKs: tens of
    /// thousands of files under one Unity install made each scan cost about 0.4 s.
    public static let defaultMaxDepth = 5

    /// The folders to scan. Missing folders are skipped.
    public let roots: [URL]
    /// How many levels below a root apps are found: 1 for apps directly in a root.
    public let maxDepth: Int

    public init(roots: [URL], maxDepth: Int = defaultMaxDepth) {
        self.roots = roots
        self.maxDepth = maxDepth
    }

    /// `/Applications`, `/System/Applications`, and `~/Applications`.
    public static func standardRoots(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            URL(filePath: "/Applications", directoryHint: .isDirectory),
            URL(filePath: "/System/Applications", directoryHint: .isDirectory),
            homeDirectory.appending(path: "Applications", directoryHint: .isDirectory),
        ]
    }

    private static let logger = LogArea.catalog.logger

    /// Scans every root and returns the apps found.
    public func scan() -> Catalog {
        let candidates = roots.flatMap { Self.bundleCandidates(under: $0, maxDepth: maxDepth) }
        // Real bundles before symbolic links, then by path, so duplicates resolve the same way every time.
        let ordered = candidates.sorted { ($0.isSymbolicLink ? 1 : 0, $0.path) < ($1.isSymbolicLink ? 1 : 0, $1.path) }

        var seenBundlePaths = Set<String>()
        var apps: [InstalledApp] = []
        for candidate in ordered where seenBundlePaths.insert(candidate.bundleURL.standardizedFilePath).inserted {
            if let app = Self.app(from: candidate) {
                apps.append(app)
            }
        }
        Self.logger.info("Catalog scan found \(apps.count, privacy: .public) apps")
        return Catalog(apps)
    }

    /// A `.app` entry found on disk, before its `Info.plist` is read.
    private struct BundleCandidate {
        /// The path where the entry was found, standardized.
        let path: String
        /// The bundle itself, with symbolic links resolved.
        let bundleURL: URL
        let isSymbolicLink: Bool
    }

    private static func bundleCandidates(under root: URL, maxDepth: Int) -> [BundleCandidate] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false), isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            logger.debug("Skipping missing app folder \(root.path(percentEncoded: false))")
            return []
        }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                // Not `.skipsHiddenFiles`: the `/Applications/Safari.app` link carries the hidden file flag.
                options: [.skipsPackageDescendants],
                errorHandler: { url, error in
                    logger.error("Cannot read \(url.path(percentEncoded: false)): \(error.localizedDescription)")
                    return true
                }
            )
        else {
            logger.error("Cannot enumerate \(root.path(percentEncoded: false))")
            return []
        }

        var candidates: [BundleCandidate] = []
        for case let url as URL in enumerator {
            let isDotName = url.lastPathComponent.hasPrefix(".")
            let isApp = !isDotName && url.pathExtension.lowercased() == "app"
            // A folder whose contents are not scanned: one with a dot name, or one at the depth limit. The root's
            // entries are at level 1.
            let isPruned = isDotName || (!isApp && enumerator.level >= maxDepth)
            guard isApp || isPruned else {
                continue
            }
            do {
                let values = try url.resourceValues(forKeys: keys)
                if isPruned {
                    // Only after a directory: after a file, `skipDescendants()` skips the rest of its folder.
                    if values.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                } else if values.isSymbolicLink == true {
                    let target = url.resolvingSymlinksInPath()
                    guard try target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                        continue
                    }
                    candidates.append(
                        BundleCandidate(path: url.standardizedFilePath, bundleURL: target, isSymbolicLink: true)
                    )
                } else if values.isDirectory == true {
                    candidates.append(
                        BundleCandidate(
                            path: url.standardizedFilePath,
                            bundleURL: url.resolvingSymlinksInPath(),
                            isSymbolicLink: false
                        )
                    )
                }
            } catch {
                logger.error("Cannot inspect \(url.path(percentEncoded: false)): \(error.localizedDescription)")
            }
        }
        return candidates
    }

    /// The app for a candidate, or nil when the bundle has no `Info.plist` and so cannot be launched.
    private static func app(from candidate: BundleCandidate) -> InstalledApp? {
        // Reads the bundle's Info.plist fresh on every scan, unlike `Bundle`, which caches it for the
        // life of the process. Wrapped iOS apps are read through their `WrappedBundle` link.
        guard
            let info = CFBundleCopyInfoDictionaryInDirectory(candidate.bundleURL as CFURL) as? [String: Any],
            !info.isEmpty
        else {
            logger.debug("Skipping \(candidate.path): no Info.plist")
            return nil
        }
        let bundleIdentifier = (info["CFBundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return InstalledApp(
            id: AppID(path: candidate.path, bundleIdentifier: bundleIdentifier),
            displayName: displayName(atPath: candidate.path),
            version: info["CFBundleShortVersionString"] as? String,
            categoryIdentifier: info["LSApplicationCategoryType"] as? String,
            bundleURL: candidate.bundleURL
        )
    }

    /// The name Finder shows, without the `.app` extension even when Finder shows extensions.
    private static func displayName(atPath path: String) -> String {
        let name = FileManager.default.displayName(atPath: path)
        return name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

extension URL {
    /// The standardized file path, without a trailing slash, so equal locations compare equal.
    fileprivate var standardizedFilePath: String {
        AppID.standardizedPath(path(percentEncoded: false))
    }
}
