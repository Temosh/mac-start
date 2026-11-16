/// One screen of the grid.
public struct Page: Hashable, Sendable, Codable {
    /// The page's slots in reading order. Reconcile keeps the count at or below the page capacity.
    public var items: [Item]

    public init(items: [Item] = []) {
        self.items = items
    }
}
