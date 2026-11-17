import MacStartCore
import SwiftUI

/// The pages side by side in one row, moved to the current page. A two-finger swipe moves the row with the
/// fingers; the controller then settles it on a page.
struct PagedGridView: View {
    let pages: [Page]
    let state: OverlayState
    let selection: GridPosition?
    let drag: DragSession?
    let metrics: GridMetrics
    let store: LayoutStore
    let icons: IconProvider
    let actions: OverlayActions

    var body: some View {
        HStack(spacing: 0) {
            ForEach(pages.indices, id: \.self) { index in
                PageView(
                    items: pages[index].items,
                    pageIndex: index,
                    selectedSlot: selection?.page == index ? selection?.slot : nil,
                    drag: drag,
                    state: state,
                    metrics: metrics,
                    store: store,
                    icons: icons,
                    actions: actions
                )
                .frame(width: metrics.overlaySize.width, height: metrics.overlaySize.height)
            }
        }
        .frame(width: metrics.overlaySize.width, height: metrics.overlaySize.height, alignment: .leading)
        .modifier(PagerOffset(state: state, pageWidth: metrics.overlaySize.width))
    }
}

/// Moves the row of pages to the current page, plus the offset of a swipe in progress. The state is read here, in
/// a modifier, so swipe frames move the row without rebuilding the pages inside it.
struct PagerOffset: ViewModifier {
    let state: OverlayState
    let pageWidth: CGFloat

    func body(content: Content) -> some View {
        content.offset(x: -CGFloat(state.currentPage) * pageWidth + state.pageOffset)
    }
}

/// Places a tile. The dragged tile follows the pointer, read here, in a modifier, so pointer moves only move that
/// one tile.
struct TilePosition: ViewModifier {
    let state: OverlayState
    let position: CGPoint
    let followsDrag: Bool

    func body(content: Content) -> some View {
        content.position(followsDrag ? (state.dragTileCenter ?? position) : position)
    }
}

/// One page of the grid, or the search results. A click between items closes the overlay. During a drag, the
/// items make room for the dragged item where it would land.
struct PageView: View {
    let items: [Item]
    /// The page's index, or nil for search results, which cannot be dragged.
    let pageIndex: Int?
    /// The keyboard selection on this page.
    let selectedSlot: Int?
    let drag: DragSession?
    let state: OverlayState
    let metrics: GridMetrics
    let store: LayoutStore
    let icons: IconProvider
    let actions: OverlayActions

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { actions.dismiss() }
                .emptySpaceMenu(actions)
            ForEach(entries, id: \.item.id) { entry in
                GridItemView(
                    item: entry.item,
                    isSelected: entry.slot == selectedSlot,
                    isFolderTarget: entry.isFolderTarget,
                    editMark: editMark(for: entry.item),
                    style: metrics.tileStyle,
                    location: pageIndex.map { .slot(GridPosition(page: $0, slot: entry.slot)) },
                    store: store,
                    icons: icons,
                    actions: actions
                )
                .frame(width: metrics.cellSize.width, height: metrics.cellSize.height)
                // The dragged tile stays invisible under the dragged copy, because its gesture lives on it. When the
                // drop shows it again, it appears right where the copy was and glides into its slot from there.
                .opacity(entry.isHidden ? 0 : 1)
                .animation(nil, value: entry.isDragged)
                .scaleEffect(entry.isDragged ? 1.08 : 1)
                .modifier(
                    TilePosition(
                        state: state,
                        position: metrics.center(ofSlot: entry.displaySlot),
                        followsDrag: entry.followsDrag
                    )
                )
                .animation(.easeInOut(duration: 0.2), value: entry.displaySlot)
                .animation(.easeOut(duration: 0.2), value: entry.isDragged)
            }
        }
    }

    /// The tile's mark in edit mode, or nil outside it.
    private func editMark(for item: Item) -> EditMark? {
        guard state.isEditing else {
            return nil
        }
        return state.editSelection.contains(item.id) ? .selected : .unselected
    }

    private struct Entry {
        let item: Item
        /// The item's slot in the layout.
        let slot: Int
        /// The slot the item shows in during a drag.
        let displaySlot: Int
        let isDragged: Bool
        /// True for the dragged tile on the page under the drag, the only page whose coordinates match the
        /// overlay's.
        let followsDrag: Bool
        let isFolderTarget: Bool
        /// True for the dragged tile, and for a tile pushed past the last slot until the drop moves it to the next
        /// page.
        let isHidden: Bool
    }

    private var entries: [Entry] {
        guard let pageIndex, let drag else {
            return items.enumerated().map { slot, item in
                Entry(
                    item: item,
                    slot: slot,
                    displaySlot: slot,
                    isDragged: false,
                    followsDrag: false,
                    isFolderTarget: false,
                    isHidden: false
                )
            }
        }
        var draggedSlot: Int?
        if case .slot(let source) = drag.source, source.page == pageIndex {
            draggedSlot = source.slot
        }
        // Inside the open folder, the folder's panel shows the gap instead of the page.
        let isOverThisPage = drag.page == pageIndex && drag.folderGapIndex == nil
        let gapSlot = isOverThisPage ? drag.gapSlot : nil
        let folderTargetSlot = isOverThisPage ? drag.folderTargetSlot : nil

        var result: [Entry] = []
        var visibleIndex = 0
        for (slot, item) in items.enumerated() {
            if slot == draggedSlot {
                result.append(
                    Entry(
                        item: item,
                        slot: slot,
                        displaySlot: slot,
                        isDragged: true,
                        followsDrag: drag.page == pageIndex,
                        isFolderTarget: false,
                        isHidden: true
                    )
                )
                continue
            }
            let displaySlot = gapSlot.map { visibleIndex >= $0 ? visibleIndex + 1 : visibleIndex } ?? visibleIndex
            result.append(
                Entry(
                    item: item,
                    slot: slot,
                    displaySlot: displaySlot,
                    isDragged: false,
                    followsDrag: false,
                    isFolderTarget: visibleIndex == folderTargetSlot,
                    isHidden: displaySlot >= metrics.pageCapacity
                )
            )
            visibleIndex += 1
        }
        return result
    }
}

/// The dots under the grid, one per page. A click on a dot shows that page.
struct PageIndicator: View {
    let pageCount: Int
    let currentPage: Int
    let isHighContrast: Bool
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(page == currentPage ? Color.white : Color.white.opacity(isHighContrast ? 0.6 : 0.35))
                    .frame(width: 8, height: 8)
                    .padding(5)
                    .contentShape(Circle())
                    .onTapGesture { select(page) }
                    .accessibilityElement()
                    .accessibilityLabel("Page \(page + 1) of \(pageCount)")
                    .accessibilityAddTraits(page == currentPage ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
