import MacStartCore
import SwiftUI

/// What the overlay's views can ask the controller to do.
struct OverlayActions {
    let launch: @MainActor (InstalledApp) -> Void
    let dismiss: @MainActor () -> Void
    let showPage: @MainActor (Int) -> Void
    let openFolder: @MainActor (UUID) -> Void
    let closeFolder: @MainActor () -> Void
    let renameFolder: @MainActor (UUID, String) -> Void
    let removeFromFolder: @MainActor (UUID, Int) -> Void
    let showInFinder: @MainActor (InstalledApp) -> Void
    let hide: @MainActor (InstalledApp) -> Void
    let dragChanged: @MainActor (DragUpdate) -> Void
    let dragEnded: @MainActor () -> Void
}

/// The overlay's content: the search field over the paged grid and its page dots, the search results, or the
/// loading and empty states, plus the open folder and the tile being dragged.
struct OverlayView: View {
    /// The coordinate space of the whole overlay, which drag locations use.
    static let coordinateSpace = "overlay"

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
                content(metrics: metrics)
                folderPanel(metrics: metrics)
                SearchField(query: $state.query, isFocused: $isSearchFocused, isHighContrast: contrast == .increased)
                    .position(x: geometry.size.width / 2, y: metrics.topInset / 2)
                DragLayer(state: state, style: metrics.tileStyle, store: store, icons: icons)
            }
            // One drag gesture for the whole overlay. The drag coordinator finds the tile under the press, so the
            // tiles carry no gestures, and the views under a drag can go away without ending it.
            .simultaneousGesture(dragGesture(metrics: metrics))
            .coordinateSpace(.named(Self.coordinateSpace))
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
    private func content(metrics: GridMetrics) -> some View {
        if !store.hasLoaded {
            ProgressView()
                .controlSize(.large)
        } else if state.isSearching {
            searchResults(metrics: metrics)
        } else if store.layout.placedAppIDs.isEmpty {
            message("No apps found")
        } else {
            PagedGridView(
                pages: store.layout.pages,
                state: state,
                selection: state.selection,
                drag: state.drag,
                metrics: metrics,
                store: store,
                icons: icons,
                actions: actions
            )
            // The custom pager gives VoiceOver's scroll commands the same page turns a swipe makes.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Apps")
            .accessibilityValue("Page \(state.currentPage + 1) of \(store.layout.pages.count)")
            .accessibilityScrollAction { edge in
                switch edge {
                case .leading: actions.showPage(state.currentPage - 1)
                case .trailing: actions.showPage(state.currentPage + 1)
                default: break
                }
            }
            if store.layout.pages.count > 1 {
                VStack {
                    Spacer()
                    PageIndicator(
                        pageCount: store.layout.pages.count,
                        currentPage: state.currentPage,
                        isHighContrast: contrast == .increased,
                        select: { actions.showPage($0) }
                    )
                    .padding(.bottom, metrics.bottomInset * 0.35)
                }
            }
        }
    }

    @ViewBuilder
    private func searchResults(metrics: GridMetrics) -> some View {
        let results = store.searchResults(matching: state.query)
        if results.isEmpty {
            message("No results")
        } else {
            PageView(
                items: results.map { .app($0.id) },
                pageIndex: nil,
                selectedSlot: state.selection?.slot,
                drag: nil,
                state: state,
                metrics: metrics,
                store: store,
                icons: icons,
                actions: actions
            )
            .frame(width: metrics.overlaySize.width, height: metrics.overlaySize.height)
        }
    }

    private func dragGesture(metrics: GridMetrics) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                actions.dragChanged(
                    DragUpdate(
                        location: value.location,
                        startLocation: value.startLocation,
                        grid: metrics,
                        folderPanel: openFolderMetrics(grid: metrics)
                    )
                )
            }
            .onEnded { _ in
                actions.dragEnded()
            }
    }

    /// The geometry of the open folder's panel, if a folder is open.
    private func openFolderMetrics(grid: GridMetrics) -> FolderPanelMetrics? {
        state.openFolderID
            .flatMap { store.folder(withID: $0) }
            .map { FolderPanelMetrics(grid: grid, appCount: $0.apps.count) }
    }

    /// The open folder's panel.
    @ViewBuilder
    private func folderPanel(metrics: GridMetrics) -> some View {
        if let folderID = state.openFolderID, let folder = store.folder(withID: folderID) {
            FolderPanelView(
                folder: folder,
                metrics: FolderPanelMetrics(grid: metrics, appCount: folder.apps.count),
                state: state,
                store: store,
                icons: icons,
                actions: actions
            )
            .id(folderID)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.title2)
            .foregroundStyle(.white.opacity(0.85))
            .allowsHitTesting(false)
    }
}

/// The copy of the dragged tile that follows the pointer. It reads the pointer itself, so pointer moves redraw only
/// this view.
struct DragLayer: View {
    let state: OverlayState
    let style: TileStyle
    let store: LayoutStore
    let icons: IconProvider

    var body: some View {
        if let drag = state.drag, let center = state.dragTileCenter {
            DraggedTileView(item: drag.item, style: style, store: store, icons: icons)
                .position(center)
                .allowsHitTesting(false)
        }
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
