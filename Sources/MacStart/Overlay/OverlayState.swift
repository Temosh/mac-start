import MacStartCore
import Observation

/// The overlay's view state, shared by the controller and the SwiftUI views.
@MainActor
@Observable
final class OverlayState {
    /// Drives the show and hide animation.
    var isPresented = false
    /// The page the grid shows, bound to the scroll position. Nil while a swipe is between pages.
    var currentPage: Int? = 0
    /// The search text. Any text besides whitespace replaces the pages with one grid of results.
    var query = "" {
        didSet {
            guard query != oldValue else {
                return
            }
            // The best result is selected, so Return launches it.
            selection = isSearching ? GridPosition(page: 0, slot: 0) : nil
        }
    }
    /// The keyboard selection. While searching, it points into the results, which count as page 0.
    var selection: GridPosition?
    /// Bumped to move keyboard focus to the search field.
    var searchFocusRequest = 0

    var isSearching: Bool {
        !query.allSatisfy(\.isWhitespace)
    }

    /// Moves to the last page when the current one no longer exists.
    func clampPage(toPageCount pageCount: Int) {
        if let currentPage, currentPage >= pageCount {
            self.currentPage = max(pageCount - 1, 0)
        }
    }

    /// Clears the search and the selection, for the next time the overlay opens.
    func reset() {
        query = ""
        selection = nil
    }
}
