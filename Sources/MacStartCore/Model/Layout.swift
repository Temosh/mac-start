/// The user's arrangement: ordered pages, plus the apps hidden from the grid and from search.
///
/// `reconciled(with:pageCapacity:)` turns any layout into one that satisfies the invariants in
/// `docs/domain-model.md`.
public struct Layout: Hashable, Sendable {
    public var pages: [Page]
    /// Hidden apps. Uninstalled apps stay here, so a reinstalled app stays hidden.
    public var hidden: Set<AppID>

    public init(pages: [Page] = [Page()], hidden: Set<AppID> = []) {
        self.pages = pages
        self.hidden = hidden
    }

    /// One empty page and nothing hidden: the layout before the first reconcile.
    public static let empty = Layout()

    /// Every placed app in reading order: page, then slot, then position inside a folder.
    public var placedAppIDs: [AppID] {
        pages.flatMap { $0.items.flatMap(\.appIDs) }
    }
}

extension Layout: Codable {
    private enum CodingKeys: String, CodingKey {
        case pages
        case hidden
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pages = try container.decode([Page].self, forKey: .pages)
        hidden = Set(try container.decode([AppID].self, forKey: .hidden))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pages, forKey: .pages)
        // Sorted, so the same layout always produces the same file.
        try container.encode(hidden.sorted { $0.path < $1.path }, forKey: .hidden)
    }
}
