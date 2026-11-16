import CoreGraphics

/// The geometry of the grid for one overlay size and grid size.
struct GridMetrics: Equatable {
    let columns: Int
    let rows: Int
    /// The area the grid's cells fill, in overlay coordinates.
    let gridFrame: CGRect
    let cellSize: CGSize
    let iconSize: CGFloat
    let labelFontSize: CGFloat
    /// The height below the grid, where the page dots sit.
    let bottomInset: CGFloat

    init(overlaySize: CGSize, columns: Int, rows: Int) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
        let horizontalInset = overlaySize.width * 0.07
        // The space above the grid is kept for the search field.
        let topInset = max(overlaySize.height * 0.11, 72)
        bottomInset = max(overlaySize.height * 0.09, 64)
        gridFrame = CGRect(
            x: horizontalInset,
            y: topInset,
            width: max(overlaySize.width - 2 * horizontalInset, 1),
            height: max(overlaySize.height - topInset - bottomInset, 1)
        )
        cellSize = CGSize(
            width: gridFrame.width / CGFloat(self.columns),
            height: gridFrame.height / CGFloat(self.rows)
        )
        iconSize = min(cellSize.width * 0.6, cellSize.height * 0.62, 160).rounded()
        labelFontSize = min(max((iconSize * 0.12).rounded(), 11), 15)
    }

    /// The center of a slot. Slots count in reading order from the top-left cell.
    func center(ofSlot slot: Int) -> CGPoint {
        let column = slot % columns
        let row = slot / columns
        return CGPoint(
            x: gridFrame.minX + cellSize.width * (CGFloat(column) + 0.5),
            y: gridFrame.minY + cellSize.height * (CGFloat(row) + 0.5)
        )
    }
}
