import CoreGraphics

/// The geometry of the open folder's panel: centered over the grid, with the folder name on top and the apps in
/// rows below, spaced as in the grid. A folder with many apps gets smaller tiles, so every app fits.
struct FolderPanelMetrics: Equatable {
    static let padding: CGFloat = 28
    /// From the panel's top edge to the top of the folder name's line.
    static let titleTop: CGFloat = 28
    /// The folder name's line, for its 22 pt font.
    static let titleHeight: CGFloat = 27
    /// From the bottom of the folder name's line to the top of the first row's icon artwork.
    static let titleGap: CGFloat = 30

    /// The panel, in overlay coordinates.
    let frame: CGRect
    let columns: Int
    let rows: Int
    let cellSize: CGSize
    let tileStyle: TileStyle
    /// The top-left corner of the first cell.
    private let contentOrigin: CGPoint

    init(grid: GridMetrics, appCount: Int) {
        let count = max(appCount, 1)
        columns = min(count, grid.columns)
        rows = (count + columns - 1) / columns
        let header = Self.titleTop + Self.titleHeight + Self.titleGap
        let availableHeight = max(grid.overlaySize.height * 0.8 - header - Self.padding, 1)
        let scale = min(1, availableHeight / (CGFloat(rows) * grid.cellSize.height))
        cellSize = CGSize(width: grid.cellSize.width * scale, height: grid.cellSize.height * scale)
        tileStyle = TileStyle(
            iconSize: (grid.iconSize * scale).rounded(),
            labelFontSize: max((grid.labelFontSize * scale).rounded(), 10),
            width: cellSize.width * 0.9
        )
        // The first row's cells start above the end of the header by as much as the artwork sits below a cell's
        // top: the room around the tile in its cell, the tile's padding, and the icon's clear margin.
        let artworkInset = (cellSize.height - tileStyle.height) / 2 + tileStyle.padding + tileStyle.iconArtworkInset
        let cellsTop = header - artworkInset
        let contentWidth = CGFloat(columns) * cellSize.width
        let width = max(contentWidth + 2 * Self.padding, 360)
        let height = cellsTop + CGFloat(rows) * cellSize.height + Self.padding
        frame = CGRect(
            x: (grid.overlaySize.width - width) / 2,
            y: (grid.overlaySize.height - height) / 2,
            width: width,
            height: height
        )
        contentOrigin = CGPoint(x: frame.midX - contentWidth / 2, y: frame.minY + cellsTop)
    }

    /// The center of the folder name field.
    var titleCenter: CGPoint {
        CGPoint(x: frame.midX, y: frame.minY + Self.titleTop + Self.titleHeight / 2)
    }

    /// The center of a slot, in reading order from the top-left cell.
    func center(ofSlot slot: Int) -> CGPoint {
        CGPoint(
            x: contentOrigin.x + cellSize.width * (CGFloat(slot % columns) + 0.5),
            y: contentOrigin.y + cellSize.height * (CGFloat(slot / columns) + 0.5)
        )
    }

    /// The slot whose cell contains `point`, or nil outside the panel's cells.
    func slot(containing point: CGPoint) -> Int? {
        let cells = CGRect(
            origin: contentOrigin,
            size: CGSize(width: CGFloat(columns) * cellSize.width, height: CGFloat(rows) * cellSize.height)
        )
        return cells.contains(point) ? slot(at: point) : nil
    }

    /// The slot of the cell under `point`, clamped to the panel's cells.
    func slot(at point: CGPoint) -> Int {
        let column = Int(((point.x - contentOrigin.x) / cellSize.width).rounded(.down))
        let row = Int(((point.y - contentOrigin.y) / cellSize.height).rounded(.down))
        return min(max(row, 0), rows - 1) * columns + min(max(column, 0), columns - 1)
    }
}
