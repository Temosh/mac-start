import CoreGraphics

/// The geometry of the open folder's panel: centered over the grid, with the folder name on top and the apps in
/// rows below. A folder with many apps gets smaller tiles, so every app fits.
struct FolderPanelMetrics: Equatable {
    static let padding: CGFloat = 28
    static let titleHeight: CGFloat = 56

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
        let availableHeight = max(grid.overlaySize.height * 0.8 - Self.titleHeight - 2 * Self.padding, 1)
        let scale = min(1, availableHeight / (CGFloat(rows) * grid.cellSize.height))
        cellSize = CGSize(width: grid.cellSize.width * scale, height: grid.cellSize.height * scale)
        tileStyle = TileStyle(
            iconSize: (grid.iconSize * scale).rounded(),
            labelFontSize: max((grid.labelFontSize * scale).rounded(), 10),
            width: cellSize.width * 0.9
        )
        let contentWidth = CGFloat(columns) * cellSize.width
        let width = max(contentWidth + 2 * Self.padding, 360)
        let height = Self.titleHeight + CGFloat(rows) * cellSize.height + 2 * Self.padding
        frame = CGRect(
            x: (grid.overlaySize.width - width) / 2,
            y: (grid.overlaySize.height - height) / 2,
            width: width,
            height: height
        )
        contentOrigin = CGPoint(x: frame.midX - contentWidth / 2, y: frame.minY + Self.padding + Self.titleHeight)
    }

    /// The center of the folder name field.
    var titleCenter: CGPoint {
        CGPoint(x: frame.midX, y: frame.minY + Self.padding + Self.titleHeight / 2)
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
