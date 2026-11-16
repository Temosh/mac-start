/// A slot on a page of the grid.
public struct GridPosition: Hashable, Sendable {
    public var page: Int
    public var slot: Int

    public init(page: Int, slot: Int) {
        self.page = page
        self.slot = slot
    }
}

/// A direction of keyboard movement in the grid.
public enum GridDirection: Sendable {
    case left
    case right
    case up
    case down
}

/// Moves a keyboard selection through pages of grid items, like the arrow keys in Launchpad.
public struct GridNavigation: Sendable {
    /// Items per row.
    public let columns: Int
    /// The number of items on each page, in page order.
    public let itemCounts: [Int]

    public init(columns: Int, itemCounts: [Int]) {
        self.columns = max(columns, 1)
        self.itemCounts = itemCounts
    }

    /// The selection after one arrow key press.
    ///
    /// Without a selection on `currentPage`, the first press selects that page's first item. Left from the
    /// first column and right from the last column or the last item go to the same row of the previous or next
    /// page. Down into a shorter last row selects that row's last item. A move past the grid's outer edge keeps
    /// the selection. Returns nil only when the current page has no items.
    public func position(
        after direction: GridDirection,
        from selection: GridPosition?,
        onPage currentPage: Int
    ) -> GridPosition? {
        guard let selection, selection.page == currentPage, isValid(selection) else {
            return itemCount(onPage: currentPage) > 0 ? GridPosition(page: currentPage, slot: 0) : nil
        }
        let count = itemCount(onPage: selection.page)
        let column = selection.slot % columns
        let row = selection.slot / columns

        switch direction {
        case .left:
            if column > 0 {
                return GridPosition(page: selection.page, slot: selection.slot - 1)
            }
            return position(onPage: selection.page - 1, row: row, column: columns - 1) ?? selection
        case .right:
            if column < columns - 1, selection.slot + 1 < count {
                return GridPosition(page: selection.page, slot: selection.slot + 1)
            }
            return position(onPage: selection.page + 1, row: row, column: 0) ?? selection
        case .up:
            return row > 0 ? GridPosition(page: selection.page, slot: selection.slot - columns) : selection
        case .down:
            let nextRowStart = (row + 1) * columns
            guard nextRowStart < count else {
                return selection
            }
            return GridPosition(page: selection.page, slot: min(selection.slot + columns, count - 1))
        }
    }

    private func itemCount(onPage page: Int) -> Int {
        itemCounts.indices.contains(page) ? itemCounts[page] : 0
    }

    private func isValid(_ position: GridPosition) -> Bool {
        position.slot >= 0 && position.slot < itemCount(onPage: position.page)
    }

    /// The slot at `row` and `column` on `page`, clamped to the page's last item, or nil when the page has none.
    private func position(onPage page: Int, row: Int, column: Int) -> GridPosition? {
        let count = itemCount(onPage: page)
        guard count > 0 else {
            return nil
        }
        return GridPosition(page: page, slot: min(row * columns + column, count - 1))
    }
}
