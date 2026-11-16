import MacStartCore
import SwiftUI

/// The pages side by side in a paged horizontal scroll view, so a two-finger swipe moves one page.
struct PagedGridView: View {
    let pages: [Page]
    @Binding var currentPage: Int?
    let selection: GridPosition?
    let drag: DragSession?
    let metrics: GridMetrics
    let store: LayoutStore
    let icons: IconProvider
    let actions: OverlayActions

    var body: some View {
        ScrollView(.horizontal) {
            // Not lazy: the page a drag started on keeps its tiles while other pages show, because removing the
            // dragged tile would end its drag gesture.
            HStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    PageView(
                        items: pages[index].items,
                        pageIndex: index,
                        selectedSlot: selection?.page == index ? selection?.slot : nil,
                        drag: drag,
                        metrics: metrics,
                        store: store,
                        icons: icons,
                        actions: actions
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentPage)
        .scrollIndicators(.hidden)
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
    let metrics: GridMetrics
    let store: LayoutStore
    let icons: IconProvider
    let actions: OverlayActions

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { actions.dismiss() }
            ForEach(entries, id: \.item.id) { entry in
                GridItemView(
                    item: entry.item,
                    isSelected: entry.slot == selectedSlot,
                    isFolderTarget: entry.isFolderTarget,
                    style: metrics.tileStyle,
                    dragContext: pageIndex.map { page in
                        DragContext(
                            source: .slot(GridPosition(page: page, slot: entry.slot)), grid: metrics, folderPanel: nil)
                    },
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
                .position(entry.position)
                .animation(.easeInOut(duration: 0.2), value: entry.displaySlot)
                .animation(.easeOut(duration: 0.2), value: entry.isDragged)
            }
        }
    }

    private struct Entry {
        let item: Item
        /// The item's slot in the layout.
        let slot: Int
        /// The slot the item shows in during a drag.
        let displaySlot: Int
        let isDragged: Bool
        let isFolderTarget: Bool
        /// Where the tile's center shows: its display slot, or under the dragged copy while it is dragged.
        let position: CGPoint
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
                    isFolderTarget: false,
                    position: metrics.center(ofSlot: slot),
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
                // Only on the page under the drag does the overlay's coordinate space match this page's.
                let position = drag.page == pageIndex ? drag.tileCenter : metrics.center(ofSlot: slot)
                result.append(
                    Entry(
                        item: item,
                        slot: slot,
                        displaySlot: slot,
                        isDragged: true,
                        isFolderTarget: false,
                        position: position,
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
                    isFolderTarget: visibleIndex == folderTargetSlot,
                    position: metrics.center(ofSlot: displaySlot),
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
