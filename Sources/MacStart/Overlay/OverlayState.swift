import CoreGraphics
import Foundation
import MacStartCore
import Observation

/// The overlay's view state, shared by the controller and the SwiftUI views.
@MainActor
@Observable
final class OverlayState {
    /// How long a folder's panel takes to grow out of its icon or to shrink back into it.
    static let folderZoomDuration = 0.2

    /// True from the moment the overlay shows until it starts to hide.
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
    /// The folder that just closed, whose panel shrinks back into its icon before it goes away.
    private(set) var closingFolderID: UUID?
    /// True once the open folder's panel has finished growing. Until then it takes no clicks and no hover, so a
    /// tile that passes under the pointer while the panel grows is not left hovered.
    private(set) var isFolderSettled = false
    /// The keyboard selection inside the open folder, as an index into its apps.
    var folderSelection: Int?
    /// True while the open folder's name is being edited, so its field gets the arrow keys and Return.
    var isEditingFolderName = false
    /// The drag in progress.
    var drag: DragSession?
    /// The rectangle that selects tiles in edit mode, in overlay coordinates, while it is being drawn.
    var selectionRectangle: CGRect?
    /// True in edit mode, where a click selects an item instead of opening it.
    var isEditing = false
    /// The items selected in edit mode. They stay selected across pages and searches.
    var editSelection: Set<Item.ID> = []
    /// The item that a Shift-click selects a range from: the last one clicked in edit mode.
    var editSelectionAnchor: Item.ID?

    /// The center of the dragged tile, which follows the pointer.
    var dragTileCenter: CGPoint? {
        drag.map { $0.tileCenter(for: dragLocation) }
    }

    var isSearching: Bool {
        !query.allSatisfy(\.isWhitespace)
    }

    /// The folder whose panel is on screen: the open one, or the one that is shrinking after it closed.
    var shownFolderID: UUID? {
        openFolderID ?? closingFolderID
    }

    func openFolder(_ id: UUID) {
        openFolderID = id
        closingFolderID = nil
        isFolderSettled = false
        folderSelection = nil
        selection = nil
        afterFolderZoom { state in
            if state.openFolderID == id {
                state.isFolderSettled = true
            }
        }
    }

    /// Closes the open folder. Its panel shrinks back into the folder's icon, taking no clicks, and goes away once
    /// it has shrunk, so SwiftUI never removes views that are in the middle of a click or hovered.
    func closeFolder() {
        if let closedID = openFolderID {
            closingFolderID = closedID
            afterFolderZoom { state in
                if state.openFolderID == nil, state.closingFolderID == closedID {
                    state.closingFolderID = nil
                }
            }
        }
        openFolderID = nil
        isFolderSettled = false
        folderSelection = nil
        isEditingFolderName = false
    }

    /// Runs `body` once a folder's panel has finished growing or shrinking.
    private func afterFolderZoom(_ body: @escaping @MainActor (OverlayState) -> Void) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.folderZoomDuration))
            if let self {
                body(self)
            }
        }
    }

    /// Moves to the last page when the current one no longer exists.
    func clampPage(toPageCount pageCount: Int) {
        if currentPage >= pageCount {
            currentPage = max(pageCount - 1, 0)
        }
    }

    /// Leaves edit mode and forgets its selection.
    func endEditing() {
        isEditing = false
        editSelection = []
        editSelectionAnchor = nil
    }

    /// Clears the search, the selection, the open folder, any drag, and edit mode, for the next time the overlay
    /// opens.
    func reset() {
        query = ""
        selection = nil
        drag = nil
        selectionRectangle = nil
        pageOffset = 0
        closeFolder()
        closingFolderID = nil
        endEditing()
    }
}
