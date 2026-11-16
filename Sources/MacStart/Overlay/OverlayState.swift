import CoreGraphics
import Foundation
import MacStartCore
import Observation

/// The overlay's view state, shared by the controller and the SwiftUI views.
@MainActor
@Observable
final class OverlayState {
    /// Drives the show and hide animation.
    var isPresented = false
    /// The page the grid shows.
    var currentPage = 0
    /// How far a swipe in progress has moved the pages, in points. Only the pager reads it, so swipe frames do
    /// not rebuild the tiles.
    var pageOffset: CGFloat = 0
    /// The pointer during a drag, in overlay coordinates. It is kept apart from `drag`, which changes only when
    /// the drop target does, so a moving pointer does not rebuild the tiles.
    var dragLocation = CGPoint.zero
    /// The search text. Any text besides whitespace replaces the pages with one grid of results.
    var query = "" {
        didSet {
            guard query != oldValue else {
                return
            }
            // The best result is selected, so Return launches it.
            selection = isSearching ? GridPosition(page: 0, slot: 0) : nil
            if isSearching {
                closeFolder()
            }
        }
    }
    /// The keyboard selection. While searching, it points into the results, which count as page 0.
    var selection: GridPosition?
    /// Bumped to move keyboard focus to the search field.
    var searchFocusRequest = 0
    /// The folder whose panel is open.
    var openFolderID: UUID?
    /// The keyboard selection inside the open folder, as an index into its apps.
    var folderSelection: Int?
    /// True while the open folder's name is being edited, so its field gets the arrow keys and Return.
    var isEditingFolderName = false
    /// The drag in progress.
    var drag: DragSession?

    /// The center of the dragged tile, which follows the pointer.
    var dragTileCenter: CGPoint? {
        drag.map { $0.tileCenter(for: dragLocation) }
    }

    var isSearching: Bool {
        !query.allSatisfy(\.isWhitespace)
    }

    func openFolder(_ id: UUID) {
        openFolderID = id
        folderSelection = nil
        selection = nil
    }

    func closeFolder() {
        openFolderID = nil
        folderSelection = nil
        isEditingFolderName = false
    }

    /// Moves to the last page when the current one no longer exists.
    func clampPage(toPageCount pageCount: Int) {
        if currentPage >= pageCount {
            currentPage = max(pageCount - 1, 0)
        }
    }

    /// Clears the search, the selection, the open folder, and any drag, for the next time the overlay opens.
    func reset() {
        query = ""
        selection = nil
        drag = nil
        pageOffset = 0
        closeFolder()
    }
}
