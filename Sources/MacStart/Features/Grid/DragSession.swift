import CoreGraphics
import Foundation
import MacStartCore

/// A drag in progress. Slots and indexes count the way the overlay shows them: with the dragged item taken out.
struct DragSession: Equatable {
    /// Where the dragged item came from.
    let source: LayoutLocation
    let item: Item
    /// From the pointer to the dragged tile's center, as it was when the drag started. The tile keeps the spot
    /// where it was grabbed under the pointer.
    let grabOffset: CGSize
    /// The grid page under the drag.
    var page: Int
    /// The slot on `page` where the dragged item would land. The items from there on show one slot later.
    var gapSlot: Int?
    /// The item on `page` that the drop would turn into a folder, or add to, after the pointer rested on it.
    var folderTargetSlot: Int?
    /// While the drag is inside the open folder: the index among the folder's apps where the app would land.
    var folderGapIndex: Int?

    /// The center of the dragged tile, which aims the drop, for the pointer at `location`.
    func tileCenter(for location: CGPoint) -> CGPoint {
        CGPoint(x: location.x + grabOffset.width, y: location.y + grabOffset.height)
    }

    var draggedFolderID: UUID? {
        if case .inFolder(let folderID, _) = source {
            return folderID
        }
        return nil
    }
}

/// One step of a drag gesture, with the geometry needed to place it.
struct DragUpdate {
    let source: LayoutLocation
    let item: Item
    let location: CGPoint
    /// The pointer where the drag started.
    let startLocation: CGPoint
    let grid: GridMetrics
    let folderPanel: FolderPanelMetrics?
}

/// What a draggable tile needs to report its drag.
struct DragContext {
    let source: LayoutLocation
    let grid: GridMetrics
    let folderPanel: FolderPanelMetrics?
}

extension Item {
    var isApp: Bool {
        if case .app = self {
            return true
        }
        return false
    }
}
