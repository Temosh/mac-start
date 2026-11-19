import CoreGraphics
import Foundation
import MacStartCore

/// Turns a drag gesture into Launchpad behavior: the other icons make room where the dragged icon rests, resting
/// it on an icon makes a folder, resting at a screen edge turns the page, resting at the right edge of the last
/// page turns to a new, empty page, and leaving the open folder takes the app out.
///
/// Icons only make room after the dragged icon pauses between them. Moving the dragged icon onto a neighbor
/// therefore never pushes the neighbor away before the folder delay can start.
@MainActor
final class DragCoordinator {
    /// How long the dragged icon rests on an icon before a drop there makes a folder.
    private static let folderDelay = Duration.milliseconds(350)
    /// How long the dragged icon rests between icons before they make room.
    private static let reflowDelay = Duration.milliseconds(220)
    /// How long the pointer rests at a screen edge before the page turns, and between further turns.
    private static let edgeDelay = Duration.milliseconds(550)

    private let store: LayoutStore
    private let state: OverlayState
    /// Turns to a page, with the given changes in the same transaction as the turn.
    private let showPage: (Int, () -> Void) -> Void
    private var folderCandidateSlot: Int?
    private var folderTimer: Task<Void, Never>?
    /// The slot the gap moves to once the dragged icon rests long enough.
    private var reflowCandidateSlot: Int?
    private var reflowTimer: Task<Void, Never>?
    private var edgeTimer: Task<Void, Never>?
    private var edgeDirection = 0
    private var lastDragEnd = Date.distantPast
    /// Where a press that hit no tile started, so moving that press drags nothing.
    private var ignoredPressLocation: CGPoint?

    init(store: LayoutStore, state: OverlayState, showPage: @escaping (Int, () -> Void) -> Void) {
        self.store = store
        self.state = state
        self.showPage = showPage
    }

    /// True during a drag and right after it, so the button under the pointer does not take the release as a
    /// click.
    var suppressesClick: Bool {
        state.drag != nil || Date.now.timeIntervalSince(lastDragEnd) < 0.3
    }

    /// One step of the overlay's drag gesture. The first step finds the tile under the press. A press that hit no
    /// tile, or any press in edit mode, drags nothing.
    func update(_ update: DragUpdate) {
        if state.drag == nil {
            guard update.startLocation != ignoredPressLocation else {
                return
            }
            // Edit mode moves items with its actions, not by dragging.
            guard
                !state.isEditing,
                let tile = grabbedTile(at: update.startLocation, grid: update.grid, folderPanel: update.folderPanel)
            else {
                ignoredPressLocation = update.startLocation
                return
            }
            begin(tile, update)
        }
        guard var drag = state.drag else {
            return
        }
        state.dragLocation = update.location
        let tileCenter = drag.tileCenter(for: update.location)

        if let openFolderID = state.openFolderID, drag.draggedFolderID == openFolderID, let panel = update.folderPanel {
            if panel.frame.contains(update.location) {
                let count = max((store.folder(withID: openFolderID)?.apps.count ?? 1) - 1, 0)
                drag.folderGapIndex = min(panel.slot(at: tileCenter), count)
                commit(drag)
                return
            }
            // Leaving the folder closes it. The drag goes on in the grid, and a drop takes the app out.
            state.closeFolder()
            drag.folderGapIndex = nil
            drag.page = state.currentPage
            drag.gapSlot = nil
        }

        updateGrid(&drag, tileCenter: tileCenter, metrics: update.grid)
        commit(drag)
        updateEdgeTimer(location: update.location, metrics: update.grid)
    }

    /// Stores the drag only when it changed, because every store redraws the tiles.
    private func commit(_ drag: DragSession) {
        if state.drag != drag {
            state.drag = drag
        }
    }

    /// Commits the drop.
    func end() {
        ignoredPressLocation = nil
        guard let drag = state.drag else {
            return
        }
        // A drop before the icons made room still lands where the dragged icon is.
        let pendingSlot = reflowCandidateSlot
        stopTimers()
        state.drag = nil
        lastDragEnd = .now

        if let openFolderID = state.openFolderID, case .inFolder(openFolderID, let index) = drag.source {
            store.moveApp(inFolder: openFolderID, from: index, to: drag.folderGapIndex ?? index)
        } else if let target = drag.folderTargetSlot {
            store.dropApp(from: drag.source, onto: GridPosition(page: drag.page, slot: target))
        } else {
            let slot = pendingSlot ?? drag.gapSlot ?? itemCountWithoutDraggedItem(onPage: drag.page, drag: drag)
            // A drop on the new page adds it to the layout.
            let isMoved = store.moveItem(from: drag.source, to: GridPosition(page: drag.page, slot: slot))
            if drag.isOnNewPage, !isMoved {
                showPage(store.layout.pages.count - 1) {}
            }
        }
    }

    /// Drops nothing and puts everything back. A new page the drag waited on goes away with it.
    func cancel() {
        stopTimers()
        lastDragEnd = .now
        if state.drag?.isOnNewPage == true {
            showPage(store.layout.pages.count - 1) { state.drag = nil }
        } else {
            state.drag = nil
        }
    }

    /// A tile under a press: where it sits, what it holds, and its center.
    private struct GrabbedTile {
        let source: LayoutLocation
        let item: Item
        let center: CGPoint
    }

    /// The tile whose cell contains a press. With a folder open, only the folder's apps can be grabbed, otherwise
    /// the items of the current page. Search results cannot be dragged.
    private func grabbedTile(at point: CGPoint, grid: GridMetrics, folderPanel: FolderPanelMetrics?) -> GrabbedTile? {
        if let folderID = state.openFolderID {
            guard
                let folderPanel,
                let folder = store.folder(withID: folderID),
                let slot = folderPanel.slot(containing: point),
                folder.apps.indices.contains(slot)
            else {
                return nil
            }
            return GrabbedTile(
                source: .inFolder(folderID, index: slot),
                item: .app(folder.apps[slot]),
                center: folderPanel.center(ofSlot: slot)
            )
        }
        let pages = store.layout.pages
        guard
            !state.isSearching,
            let slot = grid.slot(containing: point),
            pages.indices.contains(state.currentPage),
            pages[state.currentPage].items.indices.contains(slot)
        else {
            return nil
        }
        return GrabbedTile(
            source: .slot(GridPosition(page: state.currentPage, slot: slot)),
            item: pages[state.currentPage].items[slot],
            center: grid.center(ofSlot: slot)
        )
    }

    private func begin(_ tile: GrabbedTile, _ update: DragUpdate) {
        var gapSlot: Int?
        var folderGapIndex: Int?
        switch tile.source {
        case .slot(let position):
            // The dragged item's own slot shows the gap, so nothing moves until the dragged icon does.
            gapSlot = position.slot
        case .inFolder(_, let index):
            folderGapIndex = index
        }
        state.dragLocation = update.location
        state.drag = DragSession(
            source: tile.source,
            item: tile.item,
            grabOffset: CGSize(
                width: tile.center.x - update.startLocation.x,
                height: tile.center.y - update.startLocation.y
            ),
            page: state.currentPage,
            gapSlot: gapSlot,
            folderTargetSlot: nil,
            folderGapIndex: folderGapIndex
        )
        state.selection = nil
        state.folderSelection = nil
    }

    /// Aims the drop: at the icon under the dragged icon after it rests there, or at the gap, which moves under
    /// the dragged icon after it rests between icons.
    private func updateGrid(_ drag: inout DragSession, tileCenter: CGPoint, metrics: GridMetrics) {
        let count = itemCountWithoutDraggedItem(onPage: drag.page, drag: drag)
        drag.isPageFull = count >= store.preferences.pageCapacity
        let hoveredSlot = metrics.slot(at: tileCenter)
        let hoveredItem = itemIndex(showingAt: hoveredSlot, gapSlot: drag.gapSlot, count: count)

        if let hoveredItem, drag.item.isApp, metrics.isNearTile(tileCenter, ofSlot: hoveredSlot) {
            stopReflowTimer()
            if folderCandidateSlot != hoveredItem {
                drag.folderTargetSlot = nil
                startFolderTimer(slot: hoveredItem, page: drag.page)
            }
            return
        }
        stopFolderTimer()
        drag.folderTargetSlot = nil
        guard !drag.isPageFull else {
            // A full page makes no room, so a drop there pushes nothing to the next page. It puts the item back.
            stopReflowTimer()
            drag.gapSlot = nil
            return
        }
        let gapSlot = min(hoveredSlot, count)
        if gapSlot == drag.gapSlot {
            stopReflowTimer()
        } else if reflowCandidateSlot != gapSlot {
            startReflowTimer(slot: gapSlot, page: drag.page)
        }
    }

    /// The index of the item that shows in `slot`, given the gap, or nil for the gap or an empty cell.
    private func itemIndex(showingAt slot: Int, gapSlot: Int?, count: Int) -> Int? {
        var index = slot
        if let gapSlot {
            guard slot != gapSlot else {
                return nil
            }
            index = slot < gapSlot ? slot : slot - 1
        }
        return index < count ? index : nil
    }

    private func itemCountWithoutDraggedItem(onPage page: Int, drag: DragSession) -> Int {
        let pages = store.layout.pages
        guard pages.indices.contains(page) else {
            return 0
        }
        if case .slot(let source) = drag.source, source.page == page {
            return pages[page].items.count - 1
        }
        return pages[page].items.count
    }

    private func startFolderTimer(slot: Int, page: Int) {
        folderTimer?.cancel()
        folderCandidateSlot = slot
        folderTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.folderDelay)
            guard !Task.isCancelled, let self, self.folderCandidateSlot == slot, var drag = self.state.drag,
                drag.page == page
            else {
                return
            }
            drag.folderTargetSlot = slot
            self.state.drag = drag
        }
    }

    private func stopFolderTimer() {
        folderTimer?.cancel()
        folderTimer = nil
        folderCandidateSlot = nil
    }

    private func startReflowTimer(slot: Int, page: Int) {
        reflowTimer?.cancel()
        reflowCandidateSlot = slot
        reflowTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.reflowDelay)
            guard !Task.isCancelled, let self, self.reflowCandidateSlot == slot, var drag = self.state.drag,
                drag.page == page
            else {
                return
            }
            drag.gapSlot = slot
            self.state.drag = drag
            self.reflowCandidateSlot = nil
        }
    }

    private func stopReflowTimer() {
        reflowTimer?.cancel()
        reflowTimer = nil
        reflowCandidateSlot = nil
    }

    /// Turns the page while the pointer rests in the left or right edge zone.
    private func updateEdgeTimer(location: CGPoint, metrics: GridMetrics) {
        let zone = max(metrics.gridFrame.minX * 0.6, 24)
        let direction = location.x < zone ? -1 : (location.x > metrics.overlaySize.width - zone ? 1 : 0)
        guard direction != edgeDirection else {
            return
        }
        edgeDirection = direction
        edgeTimer?.cancel()
        guard direction != 0 else {
            return
        }
        edgeTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.edgeDelay)
                guard !Task.isCancelled, let self else {
                    return
                }
                self.turnPage(by: direction, metrics: metrics)
            }
        }
    }

    private func turnPage(by offset: Int, metrics: GridMetrics) {
        guard var drag = state.drag, state.openFolderID == nil else {
            return
        }
        let page = drag.page + offset
        let pageCount = store.layout.pages.count
        // Past the last page waits a new, empty page. It opens only when the last page keeps items without the
        // dragged one, since otherwise the new page would just take that page's place.
        let opensNewPage =
            page == pageCount && itemCountWithoutDraggedItem(onPage: pageCount - 1, drag: drag) > 0
        guard store.layout.pages.indices.contains(page) || opensNewPage else {
            return
        }
        stopFolderTimer()
        stopReflowTimer()
        drag.page = page
        drag.isOnNewPage = opensNewPage
        drag.folderTargetSlot = nil
        let tileCenter = drag.tileCenter(for: state.dragLocation)
        let count = itemCountWithoutDraggedItem(onPage: page, drag: drag)
        drag.isPageFull = count >= store.preferences.pageCapacity
        drag.gapSlot = drag.isPageFull ? nil : min(metrics.slot(at: tileCenter), count)
        showPage(page) { state.drag = drag }
    }

    private func stopTimers() {
        stopFolderTimer()
        stopReflowTimer()
        edgeTimer?.cancel()
        edgeTimer = nil
        edgeDirection = 0
    }
}
