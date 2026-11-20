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
    @State private var zoomImage = FolderZoomImage()
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @Environment(\.isFolderZooming) private var isZooming

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
                    // A light veil, so the panel reads as glass above the darkened grid rather than as a hole in it.
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.white.opacity(0.07))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(contrast == .increased ? 0.85 : 0.3), lineWidth: 1)
                }
                .frame(width: metrics.frame.width, height: metrics.frame.height)
                // A click on the panel itself must not reach the backdrop and close the folder.
                .contentShape(Rectangle())
                .onTapGesture {}
                .position(x: metrics.frame.midX, y: metrics.frame.midY)
            // While the panel grows or shrinks, an image of the name and apps zooms in their place. It is drawn while
            // SwiftUI evaluates this body, so the first frame of a zoom already shows it.
            if isZooming, let image = zoomImage.image(isClosing: isClosing, draw: drawRestingContent) {
                Image(decorative: image, scale: displayScale)
                    .position(x: imageFrame.midX, y: imageFrame.midY)
                    .accessibilityHidden(true)
            } else {
                nameField
                apps
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
        .onChange(of: isZooming) { _, isZooming in
            if !isZooming {
                zoomImage.clear()
            }
        }
        .onDisappear {
            commitName()
        }
    }

    /// True once the folder has closed and its panel shrinks away.
    private var isClosing: Bool {
        state.openFolderID != folder.id
    }

    private var nameField: some View {
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
    }

    private var apps: some View {
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

    /// The panel's frame grown to whole pixels, so each pixel of the zoom image falls where the live views draw it.
    private var imageFrame: CGRect {
        let minX = (metrics.frame.minX * displayScale).rounded(.down) / displayScale
        let minY = (metrics.frame.minY * displayScale).rounded(.down) / displayScale
        let maxX = (metrics.frame.maxX * displayScale).rounded(.up) / displayScale
        let maxY = (metrics.frame.maxY * displayScale).rounded(.up) / displayScale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The name and apps as they look at rest, in the coordinates of `imageFrame`, for the image that zooms in their
    /// place. The renderer does not know the window's contrast, so the tiles get it from here.
    private var restingContent: some View {
        let origin = imageFrame.origin
        return ZStack(alignment: .topLeading) {
            Text(draftName.isEmpty ? "Folder name" : draftName)
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .foregroundStyle(.white.opacity(draftName.isEmpty ? 0.3 : 1))
                .frame(width: metrics.frame.width - 2 * FolderPanelMetrics.padding)
                .position(x: metrics.titleCenter.x - origin.x, y: metrics.titleCenter.y - origin.y)
            // The dragged app is hidden in the panel, as among the live tiles.
            ForEach(entries.filter { !$0.isDragged }, id: \.app.id) { entry in
                let center = metrics.center(ofSlot: entry.displaySlot)
                TileLabel(
                    title: entry.app.displayName,
                    subtitle: store.subtitle(for: entry.app),
                    isSelected: entry.index == state.folderSelection,
                    editMark: editMark(for: entry.app.id),
                    style: metrics.tileStyle
                ) {
                    Image(nsImage: icons.icon(for: entry.app, side: metrics.tileStyle.iconSize))
                        .resizable()
                        .interpolation(.high)
                }
                .frame(width: metrics.cellSize.width, height: metrics.cellSize.height)
                .position(x: center.x - origin.x, y: center.y - origin.y)
            }
        }
        .frame(width: imageFrame.width, height: imageFrame.height)
        .environment(\.tileContrast, contrast)
        .environment(\.colorScheme, .dark)
    }

    /// Draws `restingContent` into an image of `imageFrame`, at the display's scale. The renderer places every layer
    /// on whole pixels as the window does, so the image matches the live views pixel for pixel and the swap at either
    /// end of a zoom does not show; drawn into a context of its own, it would sit up to a pixel off.
    private func drawRestingContent() -> CGImage? {
        let renderer = FolderZoomImage.renderer
        renderer.content = AnyView(restingContent)
        renderer.scale = displayScale
        defer { renderer.content = AnyView(EmptyView()) }
        return renderer.cgImage
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

/// The image of the open folder's name and apps that zooms in their place, drawn once per zoom. Zooming the live
/// views would redraw their text at each frame's size, and CoreGraphics keeps the glyphs of every size it draws: about
/// 0.5 MB for each open and close.
@MainActor
private final class FolderZoomImage {
    /// One renderer for every zoom: each new renderer keeps about 1 MB of graphics memory it never returns.
    static let renderer = ImageRenderer(content: AnyView(EmptyView()))

    private var image: CGImage?
    /// True when `image` shows the panel as it closes, so a folder opened again mid-close gets a new image.
    private var isForClosing = false

    /// The image for this zoom, drawn by `draw` on the zoom's first frame.
    func image(isClosing: Bool, draw: () -> CGImage?) -> CGImage? {
        if image == nil || isForClosing != isClosing {
            image = draw()
            isForClosing = isClosing
        }
        return image
    }

    func clear() {
        image = nil
    }
}
