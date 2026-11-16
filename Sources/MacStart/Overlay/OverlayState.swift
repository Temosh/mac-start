import Observation

/// The overlay's view state, shared by the controller and the SwiftUI views.
@MainActor
@Observable
final class OverlayState {
    /// Drives the show and hide animation.
    var isPresented = false
    /// The page the grid shows, bound to the scroll position. Nil while a swipe is between pages.
    var currentPage: Int? = 0

    /// Moves to the last page when the current one no longer exists.
    func clampPage(toPageCount pageCount: Int) {
        if let currentPage, currentPage >= pageCount {
            self.currentPage = max(pageCount - 1, 0)
        }
    }
}
