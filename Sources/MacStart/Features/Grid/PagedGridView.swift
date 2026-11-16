import MacStartCore
import SwiftUI

/// The pages side by side in a paged horizontal scroll view, so a two-finger swipe moves one page.
struct PagedGridView: View {
    let pages: [Page]
    @Binding var currentPage: Int?
    let metrics: GridMetrics
    let store: LayoutStore
    let icons: IconProvider
    let actions: OverlayActions

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    PageView(items: pages[index].items, metrics: metrics, store: store, icons: icons, actions: actions)
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

/// One page of the grid. A click between items closes the overlay.
struct PageView: View {
    let items: [Item]
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
                GridItemView(item: item, metrics: metrics, store: store, icons: icons, actions: actions)
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
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(page == currentPage ? Color.white : Color.white.opacity(0.35))
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
