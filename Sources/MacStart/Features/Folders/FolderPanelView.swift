import MacStartCore
import SwiftUI

/// The open folder: a panel with the folder's name, editable in place, above its apps. The overlay dims the grid
/// behind it, where a click closes the folder. Apps can be dragged within the panel, or out of it into the grid.
struct FolderPanelView: View {
    let folder: Folder
    let metrics: FolderPanelMetrics
    let state: OverlayState
    let store: LayoutStore
    let icons: IconProvider
    let actions: OverlayActions

    @State private var draftName: String
    @FocusState private var isNameFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        folder: Folder,
        metrics: FolderPanelMetrics,
        state: OverlayState,
        store: LayoutStore,
        icons: IconProvider,
        actions: OverlayActions
    ) {
        self.folder = folder
        self.metrics = metrics
        self.state = state
        self.store = store
        self.icons = icons
        self.actions = actions
        _draftName = State(initialValue: folder.name)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(contrast == .increased ? 0.85 : 0.2), lineWidth: 1)
                }
                .frame(width: metrics.frame.width, height: metrics.frame.height)
                // A click on the panel itself must not reach the backdrop and close the folder.
                .contentShape(Rectangle())
                .onTapGesture {}
                .position(x: metrics.frame.midX, y: metrics.frame.midY)
            TextField("Folder name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .focused($isNameFocused)
                .onSubmit {
                    commitName()
                    state.searchFocusRequest += 1
                }
                .accessibilityLabel("Folder name")
                .frame(width: metrics.frame.width - 2 * FolderPanelMetrics.padding)
                .position(metrics.titleCenter)
            ForEach(entries, id: \.app.id) { entry in
                GridItemView(
                    item: .app(entry.app.id),
                    isSelected: entry.index == state.folderSelection,
                    isFolderTarget: false,
                    editMark: editMark(for: entry.app.id),
                    selectionSummary: editMark(for: entry.app.id) == .selected
                        ? EditSelectionSummary(state.editSelection, openFolder: folder) : nil,
                    style: metrics.tileStyle,
                    location: .inFolder(folder.id, index: entry.index),
                    pageCount: store.layout.pages.count,
                    store: store,
                    icons: icons,
                    actions: actions,
                    isHoverable: state.drag == nil
                )
                .frame(width: metrics.cellSize.width, height: metrics.cellSize.height)
                // As in the grid: the dragged tile hides under the dragged copy and glides into place from there.
                .opacity(entry.isDragged ? 0 : 1)
                .animation(nil, value: entry.isDragged)
                .scaleEffect(entry.isDragged ? 1.08 : 1)
                .modifier(
                    TilePosition(
                        state: state,
                        position: metrics.center(ofSlot: entry.displaySlot),
                        followsDrag: entry.isDragged
                    )
                )
                .animation(.easeInOut(duration: 0.2), value: entry.displaySlot)
                .animation(.easeOut(duration: 0.2), value: entry.isDragged)
            }
        }
        .onChange(of: isNameFocused) { _, isFocused in
            state.isEditingFolderName = isFocused
            if !isFocused {
                commitName()
            }
        }
        .onChange(of: folder.name) { _, name in
            draftName = name
        }
        .onDisappear {
            commitName()
        }
    }

    private func commitName() {
        if draftName != folder.name {
            actions.renameFolder(folder.id, draftName)
        }
    }

    /// The app's mark in edit mode, or nil outside it.
    private func editMark(for app: AppID) -> EditMark? {
        guard state.isEditing else {
            return nil
        }
        return state.editSelection.contains(.app(app)) ? .selected : .unselected
    }

    private struct Entry {
        /// The app's index in the folder.
        let index: Int
        let app: InstalledApp
        let displaySlot: Int
        let isDragged: Bool
    }

    /// The folder's apps, making room where a dragged app would land.
    private var entries: [Entry] {
        var draggedIndex: Int?
        var gapIndex: Int?
        if let drag = state.drag, case .inFolder(folder.id, let index) = drag.source {
            draggedIndex = index
            gapIndex = drag.folderGapIndex
        }
        var result: [Entry] = []
        var visibleIndex = 0
        for (index, id) in folder.apps.enumerated() {
            guard let app = store.app(for: id) else {
                continue
            }
            if index == draggedIndex {
                result.append(Entry(index: index, app: app, displaySlot: index, isDragged: true))
                continue
            }
            let displaySlot = gapIndex.map { visibleIndex >= $0 ? visibleIndex + 1 : visibleIndex } ?? visibleIndex
            result.append(
                Entry(index: index, app: app, displaySlot: displaySlot, isDragged: false)
            )
            visibleIndex += 1
        }
        return result
    }
}
