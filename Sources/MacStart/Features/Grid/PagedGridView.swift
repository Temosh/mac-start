import MacStartCore
import SwiftUI

/// The pages side by side in a paged horizontal scroll view, so a two-finger swipe moves one page.
struct PagedGridView: View {
    let pages: [Page]
    @Binding var currentPage: Int?
    let selection: GridPosition?
    let metrics: GridMetrics
    let store: LayoutStore
    let icons: IconProvider
    let actions: OverlayActions

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    PageView(
                        items: pages[index].items,
                        selectedSlot: selection?.page == index ? selection?.slot : nil,
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

/// One page of the grid, or the search results. A click between items closes the overlay.
struct PageView: View {
    let items: [Item]
    /// The keyboard selection on this page.
    let selectedSlot: Int?
    let metrics: GridMetrics
    let store: LayoutStore
    let icons: IconProvider
    let actions: OverlayActions

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { actions.dismiss() }
            ForEach(Array(items.enumerated()), id: \.element.id) { slot, item in
                GridItemView(
                    item: item,
                    isSelected: slot == selectedSlot,
                    metrics: metrics,
                    store: store,
                    icons: icons,
                    actions: actions
                )
                .frame(width: metrics.cellSize.width, height: metrics.cellSize.height)
                .position(metrics.center(ofSlot: slot))
            }
        }
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
