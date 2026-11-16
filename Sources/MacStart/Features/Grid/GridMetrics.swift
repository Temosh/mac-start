import CoreGraphics

/// The sizes of one tile: its icon, its label, and how wide the label may get.
struct TileStyle: Equatable {
    let iconSize: CGFloat
    let labelFontSize: CGFloat
    let maxLabelWidth: CGFloat
}

/// The geometry of the grid for one overlay size and grid size.
struct GridMetrics: Equatable {
    let columns: Int
    let rows: Int
    let overlaySize: CGSize
    /// The area the grid's cells fill, in overlay coordinates.
    let gridFrame: CGRect
    let cellSize: CGSize
    let iconSize: CGFloat
    let labelFontSize: CGFloat
    /// The height above the grid, where the search field sits.
    let topInset: CGFloat
    /// The height below the grid, where the page dots sit.
    let bottomInset: CGFloat

    init(overlaySize: CGSize, columns: Int, rows: Int) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
        self.overlaySize = overlaySize
        let horizontalInset = overlaySize.width * 0.07
        topInset = max(overlaySize.height * 0.11, 72)
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

    var tileStyle: TileStyle {
        TileStyle(iconSize: iconSize, labelFontSize: labelFontSize, maxLabelWidth: cellSize.width * 0.92)
    }

    /// How many items fit on one page.
    var pageCapacity: Int {
        columns * rows
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

    /// The slot of the cell under `point`, clamped to the grid.
    func slot(at point: CGPoint) -> Int {
        let column = Int(((point.x - gridFrame.minX) / cellSize.width).rounded(.down))
        let row = Int(((point.y - gridFrame.minY) / cellSize.height).rounded(.down))
        return min(max(row, 0), rows - 1) * columns + min(max(column, 0), columns - 1)
    }

    /// True when a dragged tile centered at `tileCenter` covers most of the tile in `slot`, so a drop there makes
    /// a folder.
    func isNearTile(_ tileCenter: CGPoint, ofSlot slot: Int) -> Bool {
        let slotCenter = center(ofSlot: slot)
        let dx = tileCenter.x - slotCenter.x
        let dy = tileCenter.y - slotCenter.y
        return (dx * dx + dy * dy).squareRoot() <= iconSize * 0.4
    }
}
