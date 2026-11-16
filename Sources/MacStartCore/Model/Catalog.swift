/// The apps currently installed in the scanned folders, keyed by `AppID`.
public struct Catalog: Hashable, Sendable {
    private let appsByID: [AppID: App]

    /// Creates a catalog. When two apps share one path, the first one is kept.
    public init(_ apps: some Sequence<App>) {
        appsByID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// A catalog without apps.
    public static let empty = Catalog([])

    /// Every app, in no particular order.
    public var apps: Dictionary<AppID, App>.Values {
        appsByID.values
    }

    public var count: Int {
        appsByID.count
    }

    public var isEmpty: Bool {
        appsByID.isEmpty
    }

    /// The installed app at the path of `id`, if there is one.
    public subscript(id: AppID) -> App? {
        appsByID[id]
    }

    public func contains(_ id: AppID) -> Bool {
        appsByID[id] != nil
    }
}
