import MacStartCore
import SwiftUI

/// The open folder: a panel over the dimmed grid, with the folder's name, editable in place, above its apps.
/// A click outside the panel closes it. Apps can be dragged within the panel, or out of it into the grid.
struct FolderPanelView: View {
    let folder: Folder
    /// False while a drag that left the panel is still running. The panel then stays in place, invisible,
    /// because the dragged tile's gesture lives on it.
    let isVisible: Bool
    let metrics: FolderPanelMetrics
    let grid: GridMetrics
    let state: OverlayState
    let store: LayoutStore
    let icons: IconProvider
    let actions: OverlayActions

    @State private var draftName: String
    @FocusState private var isNameFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        folder: Folder,
        isVisible: Bool,
        metrics: FolderPanelMetrics,
        grid: GridMetrics,
        state: OverlayState,
        store: LayoutStore,
        icons: IconProvider,
        actions: OverlayActions
    ) {
        self.folder = folder
        self.isVisible = isVisible
        self.metrics = metrics
        self.grid = grid
        self.state = state
        self.store = store
        self.icons = icons
        self.actions = actions
        _draftName = State(initialValue: folder.name)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(contrast == .increased ? 0.5 : 0.3)
                .contentShape(Rectangle())
                .onTapGesture { actions.closeFolder() }
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
            ForEach(entries, id: \.index) { entry in
                GridItemView(
                    item: .app(entry.app.id),
                    isSelected: entry.index == state.folderSelection,
                    isFolderTarget: false,
                    style: metrics.tileStyle,
                    dragContext: DragContext(
                        source: .inFolder(folder.id, index: entry.index),
                        grid: grid,
                        folderPanel: metrics
                    ),
                    store: store,
                    icons: icons,
                    actions: actions
                )
                .frame(width: metrics.cellSize.width, height: metrics.cellSize.height)
                .opacity(entry.isDragged ? 0 : 1)
                .position(metrics.center(ofSlot: entry.displaySlot))
                .animation(.easeInOut(duration: 0.2), value: entry.displaySlot)
            }
        }
        .opacity(isVisible ? 1 : 0)
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
            result.append(Entry(index: index, app: app, displaySlot: displaySlot, isDragged: false))
            visibleIndex += 1
        }
        return result
    }
}
