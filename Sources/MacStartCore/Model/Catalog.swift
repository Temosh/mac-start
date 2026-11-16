/// The apps currently installed in the scanned folders, keyed by `AppID`.
public struct Catalog: Hashable, Sendable {
    private let appsByID: [AppID: InstalledApp]

    /// Creates a catalog. When two apps share one path, the first one is kept.
    public init(_ apps: some Sequence<InstalledApp>) {
        appsByID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// A catalog without apps.
    public static let empty = Catalog([])

    /// Every app, in no particular order.
    public var apps: Dictionary<AppID, InstalledApp>.Values {
        appsByID.values
    }

    public var count: Int {
        appsByID.count
    }

    public var isEmpty: Bool {
        appsByID.isEmpty
    }

    /// The installed app at the path of `id`, if there is one.
    public subscript(id: AppID) -> InstalledApp? {
        appsByID[id]
    }

    public func contains(_ id: AppID) -> Bool {
        appsByID[id] != nil
    }

    /// Display names that more than one installed app uses. The grid shows the version under these names, so
    /// the apps can be told apart.
    public var sharedDisplayNames: Set<String> {
        var seen = Set<String>()
        var shared = Set<String>()
        for app in appsByID.values where !seen.insert(app.displayName).inserted {
            shared.insert(app.displayName)
        }
        return shared
    }
}
