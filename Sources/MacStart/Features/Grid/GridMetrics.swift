import CoreGraphics

/// The sizes of one tile: its icon, its label, and how wide the label may get.
struct TileStyle: Equatable {
    let iconSize: CGFloat
    let labelFontSize: CGFloat
    let maxLabelWidth: CGFloat

    /// The space around the icon and the label.
    var padding: CGFloat {
        iconSize * 0.1
    }

    /// The space between the icon and the label.
    var labelSpacing: CGFloat {
        iconSize * 0.06
    }
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

    /// The height of the search field and of the buttons beside it.
    static let toolbarHeight: CGFloat = 38

    /// The vertical center of the search field and the buttons beside it: halfway between the top of the screen
    /// and the top of the first row's icons, so the space above them matches the space below.
    var toolbarCenterY: CGFloat {
        let style = tileStyle
        // A tile is centered in its cell: padding, icon, spacing, one line of label, padding.
        let tileHeight = 2 * style.padding + iconSize + style.labelSpacing + labelFontSize * 1.2
        let iconTop = gridFrame.minY + (cellSize.height - tileHeight) / 2 + style.padding
        // App icons leave about a tenth of their size clear around the artwork.
        return (iconTop + iconSize * 0.1) / 2
    }

    /// Where the buttons beside the search field end: at the right edge of the last column's icons.
    var toolbarTrailingX: CGFloat {
        gridFrame.maxX - (cellSize.width - iconSize) / 2
    }

    /// The search field's width: wider on wider screens, within limits.
    var searchFieldWidth: CGFloat {
        min(max(overlaySize.width * 0.18, 280), 360)
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

    /// The slot whose cell contains `point`, or nil outside the grid.
    func slot(containing point: CGPoint) -> Int? {
        gridFrame.contains(point) ? slot(at: point) : nil
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
