import MacStartCore
import SwiftUI

/// What the overlay's views can ask the controller to do.
struct OverlayActions {
    /// A click on a tile: launches the app or opens the folder, or selects the tile in edit mode.
    let click: @MainActor (Item) -> Void
    let dismiss: @MainActor () -> Void
    let showPage: @MainActor (Int) -> Void
    /// Moves items to the end of a page, then shows where they went.
    let moveItems: @MainActor (Set<Item.ID>, Int) -> Void
    let closeFolder: @MainActor () -> Void
    let renameFolder: @MainActor (UUID, String) -> Void
    let removeFromFolder: @MainActor (UUID, Int) -> Void
    let showInFinder: @MainActor (InstalledApp) -> Void
    let hide: @MainActor (InstalledApp) -> Void
    let openSettings: @MainActor () -> Void
    /// Enters or leaves edit mode.
    let toggleEditing: @MainActor () -> Void
    /// Selects or deselects an item in edit mode, as a click on its badge does.
    let select: @MainActor (Item) -> Void
    let performEdit: @MainActor (EditAction) -> Void
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
                    .emptySpaceMenu(actions)
                content(metrics: metrics)
                // Under the folder panel, so an open folder dims and covers the page dots as it does the grid.
                bottomBar(metrics: metrics)
                folderPanel(metrics: metrics)
                SearchField(
                    query: $state.query,
                    isFocused: $isSearchFocused,
                    width: metrics.searchFieldWidth,
                    isHighContrast: contrast == .increased
                )
                .position(x: geometry.size.width / 2, y: metrics.toolbarCenterY)
                toolbarButtons
                    .padding(.trailing, geometry.size.width - metrics.toolbarTrailingX)
                    .frame(width: geometry.size.width, alignment: .trailing)
                    .position(x: geometry.size.width / 2, y: metrics.toolbarCenterY)
                // Over the folder panel, so edit mode works inside an open folder.
                editBar(metrics: metrics)
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
        }
    }

    /// Edit, or Done in edit mode, then Settings, at the right end of the search field's line.
    private var toolbarButtons: some View {
        HStack(spacing: 8) {
            if state.isEditing {
                DoneButton(action: actions.toggleEditing)
            } else {
                ToolbarButton(
                    systemImage: "checkmark.circle",
                    label: "Edit",
                    help: "Select apps and folders to move, group, or hide",
                    isHighContrast: contrast == .increased,
                    action: actions.toggleEditing
                )
            }
            ToolbarButton(
                systemImage: "gearshape",
                label: "Settings",
                help: "Settings (⌘,)",
                isHighContrast: contrast == .increased,
                action: actions.openSettings
            )
        }
    }

    private var showsPageDots: Bool {
        store.hasLoaded && !state.isSearching && !store.layout.placedAppIDs.isEmpty && store.layout.pages.count > 1
    }

    private var pageDots: some View {
        PageIndicator(
            pageCount: store.layout.pages.count,
            currentPage: state.currentPage,
            isHighContrast: contrast == .increased,
            select: { actions.showPage($0) }
        )
    }

    /// The page dots at the bottom of the overlay.
    private func bottomBar(metrics: GridMetrics) -> some View {
        VStack {
            Spacer()
            if showsPageDots {
                pageDots
            }
        }
        .padding(.bottom, metrics.bottomInset * 0.35)
    }

    /// The edit actions in edit mode, right above the page dots.
    private func editBar(metrics: GridMetrics) -> some View {
        VStack(spacing: 10) {
            Spacer()
            if state.isEditing {
                EditActionBar(
                    selection: state.editSelection,
                    openFolder: state.openFolderID.flatMap { store.folder(withID: $0) },
                    pageCount: store.layout.pages.count,
                    isHighContrast: contrast == .increased,
                    perform: actions.performEdit
                )
                // Holds the place of the page dots, which sit under the folder panel.
                if showsPageDots {
                    pageDots.hidden()
                }
            }
        }
        .padding(.bottom, metrics.bottomInset * 0.35)
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
                pageCount: store.layout.pages.count,
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
    let width: CGFloat
    let isHighContrast: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityHidden(true)
            TextField("Search", text: $query, prompt: Text("Search").foregroundStyle(.white.opacity(0.6)))
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused(isFocused)
                .accessibilityLabel("Search apps")
        }
        .font(.system(size: 15))
        .padding(.horizontal, 13)
        .frame(width: width, height: GridMetrics.toolbarHeight)
        .background(Capsule().fill(.white.opacity(isHighContrast ? 0.25 : 0.14)))
        .overlay(Capsule().strokeBorder(.white.opacity(isHighContrast ? 0.85 : 0.25), lineWidth: 1))
    }
}

/// The button that leaves edit mode, in the accent color so edit mode is easy to spot.
struct DoneButton: View {
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Text("Done")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: GridMetrics.toolbarHeight)
                .background(Capsule().fill(Color.accentColor))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help("Leave edit mode (Escape)")
    }
}

/// A round button beside the search field, styled like it.
struct ToolbarButton: View {
    let systemImage: String
    let label: String
    /// The tooltip.
    let help: String
    let isHighContrast: Bool
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: GridMetrics.toolbarHeight, height: GridMetrics.toolbarHeight)
                .background(Circle().fill(.white.opacity(isHighContrast ? 0.25 : 0.14)))
                .overlay(Circle().strokeBorder(.white.opacity(isHighContrast ? 0.85 : 0.25), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(help)
        .accessibilityLabel(label)
    }
}

extension View {
    /// The menu of the overlay's empty space.
    func emptySpaceMenu(_ actions: OverlayActions) -> some View {
        contextMenu {
            Button("Settings…") {
                actions.openSettings()
            }
        }
    }
}
