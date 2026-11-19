import Foundation

/// Tells the file system changes that can change the catalog from those that cannot, so a change deep inside a
/// bundle or below the scan depth starts no rescan. FSEvents reports every folder that changed under the app
/// folders, at any depth: while an app installs or updates, a write inside its bundle would otherwise rescan every
/// app folder about every two seconds.
public struct CatalogChangeFilter: Sendable {
    private let roots: [String]
    private let maxDepth: Int

    /// - Parameters:
    ///   - roots: The scanned app folders.
    ///   - maxDepth: How many levels below a root the scan finds apps, as in `CatalogScanner`.
    public init(roots: [URL], maxDepth: Int = CatalogScanner.defaultMaxDepth) {
        // FSEvents names folders by their real path, so a root reached through a symbolic link, such as a linked
        // `~/Applications`, is known by both paths.
        self.roots = roots.flatMap { root -> [String] in
            let path = AppID.standardizedPath(root.path(percentEncoded: false))
            guard let realPath = Self.realPath(of: path), realPath != path else {
                return [path]
            }
            return [path, realPath]
        }
        self.maxDepth = maxDepth
    }

    /// True when a change in the folder at `path`, as FSEvents names it, can add, remove, or update an app. That is
    /// a change in a folder whose entries the scan reads, in a bundle itself, or in a bundle's `Contents` folder,
    /// which holds its `Info.plist`. A path outside every root counts, because it cannot be judged.
    public func canChangeCatalog(path: String) -> Bool {
        let path = AppID.standardizedPath(path)
        guard let root = roots.first(where: { path == $0 || path.hasPrefix($0 == "/" ? $0 : $0 + "/") }) else {
            return true
        }
        let components = path.dropFirst(root.count).split(separator: "/")
        for (index, component) in components.enumerated() {
            // The scan skips dot folders. An app moved in or out of one also changes the folder that holds it.
            if component.hasPrefix(".") {
                return false
            }
            if component.lowercased().hasSuffix(".app") {
                let level = index + 1
                let inside = components.dropFirst(level)
                return level <= maxDepth && (inside.isEmpty || (inside.count == 1 && inside.first == "Contents"))
            }
        }
        // A folder `components.count` levels below the root, whose entries are one level deeper.
        return components.count < maxDepth
    }

    /// The path with every symbolic link resolved, or nil when it does not exist. Unlike
    /// `URL.resolvingSymlinksInPath()`, this keeps `/private` in front of `/var` and `/tmp`, as FSEvents does.
    private static func realPath(of path: String) -> String? {
        guard let resolved = realpath(path, nil) else {
            return nil
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
