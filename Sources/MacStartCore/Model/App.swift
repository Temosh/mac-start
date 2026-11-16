import Foundation

/// An installed app, as the catalog scan found it. Never persisted: the layout stores only `AppID`s.
public struct App: Hashable, Sendable, Identifiable {
    public let id: AppID
    /// The name Finder shows for the app, localized and without the `.app` extension.
    public let displayName: String
    /// `CFBundleShortVersionString`. The grid shows it under the name when several apps share one name.
    public let version: String?
    /// The bundle on disk. For a symbolic link in an app folder, this is the link's target.
    public let bundleURL: URL

    /// Creates an app. Without a `bundleURL`, the bundle is the one at `id.path`.
    public init(id: AppID, displayName: String, version: String? = nil, bundleURL: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.bundleURL = bundleURL ?? URL(filePath: id.path, directoryHint: .isDirectory)
    }

    /// Finder-like order by display name. Ties are broken by path, so the order is always the same.
    static func displayOrder(_ lhs: App, _ rhs: App) -> Bool {
        switch lhs.displayName.localizedStandardCompare(rhs.displayName) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs.id.path < rhs.id.path
        }
    }
}
