import MacStartCore
import SwiftUI

/// What the overlay's views can ask the controller to do.
struct OverlayActions {
    let launch: @MainActor (InstalledApp) -> Void
    let dismiss: @MainActor () -> Void
    let showPage: @MainActor (Int) -> Void
}

/// The overlay's content: the search field over the paged grid and its page dots, the search results, or the
/// loading and empty states.
struct OverlayView: View {
    let store: LayoutStore
    @Bindable var state: OverlayState
    let icons: IconProvider
    let actions: OverlayActions

    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            let metrics = GridMetrics(
                overlaySize: geometry.size,
                columns: store.preferences.gridColumns,
                rows: store.preferences.gridRows
            )
            ZStack {
                Color.black.opacity(contrast == .increased ? 0.45 : 0.2)
                    .contentShape(Rectangle())
                    .onTapGesture { actions.dismiss() }
                content(metrics: metrics, size: geometry.size)
                SearchField(query: $state.query, isFocused: $isSearchFocused, isHighContrast: contrast == .increased)
                    .position(x: geometry.size.width / 2, y: metrics.topInset / 2)
            }
        }
        .ignoresSafeArea()
        .scaleEffect(state.isPresented || reduceMotion ? 1 : 1.06)
        .animation(
            reduceMotion ? nil : .easeOut(duration: OverlayController.animationDuration),
            value: state.isPresented
        )
        .onChange(of: store.layout.pages.count) { _, pageCount in
            state.clampPage(toPageCount: pageCount)
        }
        .onChange(of: state.searchFocusRequest) {
            isSearchFocused = true
        }
    }

    @ViewBuilder
    private func content(metrics: GridMetrics, size: CGSize) -> some View {
        if !store.hasLoaded {
            ProgressView()
                .controlSize(.large)
        } else if state.isSearching {
            searchResults(metrics: metrics, size: size)
        } else if store.layout.placedAppIDs.isEmpty {
            message("No apps found")
        } else {
            PagedGridView(
                pages: store.layout.pages,
                currentPage: $state.currentPage,
                selection: state.selection,
                metrics: metrics,
                store: store,
                icons: icons,
                actions: actions
            )
            if store.layout.pages.count > 1 {
                VStack {
                    Spacer()
                    PageIndicator(
                        pageCount: store.layout.pages.count,
                        currentPage: state.currentPage ?? 0,
                        isHighContrast: contrast == .increased,
                        select: { actions.showPage($0) }
                    )
                    .padding(.bottom, metrics.bottomInset * 0.35)
                }
            }
        }
    }

    @ViewBuilder
    private func searchResults(metrics: GridMetrics, size: CGSize) -> some View {
        let results = store.searchResults(matching: state.query)
        if results.isEmpty {
            message("No results")
        } else {
            PageView(
                items: results.map { .app($0.id) },
                selectedSlot: state.selection?.slot,
                metrics: metrics,
                store: store,
                icons: icons,
                actions: actions
            )
            .frame(width: size.width, height: size.height)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.title2)
            .foregroundStyle(.white.opacity(0.85))
            .allowsHitTesting(false)
    }
}

/// The search field at the top of the overlay. It has the keyboard focus while the overlay is open, so typing
/// searches right away.
struct SearchField: View {
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding
    let isHighContrast: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityHidden(true)
            TextField("Search", text: $query, prompt: Text("Search").foregroundStyle(.white.opacity(0.6)))
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused(isFocused)
                .accessibilityLabel("Search apps")
        }
        .font(.system(size: 14))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 260)
        .background(Capsule().fill(.white.opacity(isHighContrast ? 0.25 : 0.14)))
        .overlay(Capsule().strokeBorder(.white.opacity(isHighContrast ? 0.85 : 0.25), lineWidth: 1))
    }
}
