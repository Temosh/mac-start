import Foundation

/// An installed app, as the catalog scan found it. Never persisted: the layout stores only `AppID`s.
public struct InstalledApp: Hashable, Sendable, Identifiable {
    public let id: AppID
    /// The name Finder shows for the app, localized and without the `.app` extension.
    public let displayName: String
    /// `CFBundleShortVersionString`. The grid shows it under the name when several apps share one name.
    public let version: String?
    /// `LSApplicationCategoryType`, for example `public.app-category.developer-tools`.
    public let categoryIdentifier: String?
    /// The bundle on disk. For a symbolic link in an app folder, this is the link's target.
    public let bundleURL: URL

    /// Creates an app. Without a `bundleURL`, the bundle is the one at `id.path`.
    public init(
        id: AppID,
        displayName: String,
        version: String? = nil,
        categoryIdentifier: String? = nil,
        bundleURL: URL? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.categoryIdentifier = categoryIdentifier
        self.bundleURL = bundleURL ?? URL(filePath: id.path, directoryHint: .isDirectory)
    }

    /// The app's App Store category as words, for example "Developer Tools", or nil when the app declares none.
    public var categoryName: String? {
        let prefix = "public.app-category."
        guard let categoryIdentifier, categoryIdentifier.hasPrefix(prefix) else {
            return nil
        }
        let words = categoryIdentifier.dropFirst(prefix.count).split(separator: "-")
        guard !words.isEmpty else {
            return nil
        }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Finder-like order by display name. Ties are broken by path, so the order is always the same.
    static func displayOrder(_ lhs: InstalledApp, _ rhs: InstalledApp) -> Bool {
        switch lhs.displayName.localizedStandardCompare(rhs.displayName) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs.id.path < rhs.id.path
        }
    }
}
