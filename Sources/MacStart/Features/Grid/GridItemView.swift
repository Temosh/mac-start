import MacStartCore
import SwiftUI

/// One tile: an app that launches on click, or a folder that opens on click. In edit mode a click selects the
/// tile instead. Tiles carry no drag gesture: the overlay has one for all of them.
struct GridItemView: View {
    let item: Item
    /// True when the keyboard selection is on this tile.
    let isSelected: Bool
    /// True while a dragged app rests on this tile, so a drop here makes or fills a folder.
    let isFolderTarget: Bool
    /// The tile's mark in edit mode, or nil outside it.
    let editMark: EditMark?
    /// For a tile selected in edit mode: what the whole selection allows. Its menu then acts on the selection.
    let selectionSummary: EditSelectionSummary?
    let style: TileStyle
    /// Where the tile sits, for the context menu. Nil for search results.
    let location: LayoutLocation?
    /// How many pages there are, for the Move to Page menu.
    let pageCount: Int
    let store: LayoutStore
    let icons: IconProvider
    let actions: OverlayActions

    var body: some View {
        tile
            .scaleEffect(isFolderTarget ? 1.15 : 1)
            .animation(.easeOut(duration: 0.15), value: isFolderTarget)
    }

    @ViewBuilder
    private var tile: some View {
        switch item {
        case .app(let id):
            if let app = store.app(for: id) {
                appTile(app)
            }
        case .folder(let folder):
            folderTile(folder)
        }
    }

    private func appTile(_ app: InstalledApp) -> some View {
        // Apps that share a name show their version, so they can be told apart.
        let subtitle = store.sharedDisplayNames.contains(app.displayName) ? app.version : nil
        return Button {
            actions.click(item)
        } label: {
            TileLabel(
                title: app.displayName,
                subtitle: subtitle,
                isSelected: isSelected,
                isHighlighted: isFolderTarget,
                editMark: editMark,
                onBadgeTap: { actions.select(item) },
                style: style
            ) {
                Image(nsImage: icons.icon(for: app, side: style.iconSize))
                    .resizable()
                    .interpolation(.high)
            }
        }
        .buttonStyle(TileButtonStyle())
        .focusEffectDisabled()
        .contextMenu {
            if let selectionSummary {
                SelectionMenuItems(
                    summary: selectionSummary,
                    pageCount: pageCount,
                    canPerform: actions.canPerformEdit,
                    perform: actions.performEdit
                )
            } else {
                Button("Hide") {
                    actions.hide(app)
                }
                Button("Show in Finder") {
                    actions.showInFinder(app)
                }
                moveToPageMenu
                if case .inFolder(let folderID, let index)? = location {
                    Button("Remove from Folder") {
                        actions.removeFromFolder(folderID, index)
                    }
                    .disabled(!actions.canRemoveFromFolder(folderID, index))
                }
            }
        }
        .accessibilityLabel(subtitle.map { "\(app.displayName), version \($0)" } ?? app.displayName)
        .accessibilityAddTraits(isMarkedSelected ? .isSelected : [])
        .accessibilityActions { selectAction }
    }

    /// Moves just this item to the end of a page.
    private var moveToPageMenu: some View {
        Menu("Move to Page") {
            PageMenuItems(pageCount: pageCount, canMove: { actions.canMoveItems([item.id], $0) }) {
                actions.moveItems([item.id], $0)
            }
        }
    }

    /// In edit mode, VoiceOver can select the tile directly, since activating a folder opens it.
    @ViewBuilder
    private var selectAction: some View {
        if let editMark {
            Button(editMark == .selected ? "Deselect" : "Select") {
                actions.select(item)
            }
        }
    }

    /// In edit mode, the edit selection is what VoiceOver reports as selected; otherwise, the keyboard selection.
    private var isMarkedSelected: Bool {
        editMark.map { $0 == .selected } ?? isSelected
    }

    private func folderTile(_ folder: Folder) -> some View {
        Button {
            actions.click(item)
        } label: {
            TileLabel(
                title: folder.name,
                subtitle: nil,
                isSelected: isSelected,
                isHighlighted: isFolderTarget,
                editMark: editMark,
                onBadgeTap: { actions.select(item) },
                style: style
            ) {
                FolderIcon(apps: folder.apps.compactMap { store.app(for: $0) }, icons: icons)
            }
        }
        .buttonStyle(TileButtonStyle())
        .focusEffectDisabled()
        .contextMenu {
            if let selectionSummary {
                SelectionMenuItems(
                    summary: selectionSummary,
                    pageCount: pageCount,
                    canPerform: actions.canPerformEdit,
                    perform: actions.performEdit
                )
            } else {
                moveToPageMenu
            }
        }
        .accessibilityLabel("\(folder.name) folder")
        .accessibilityAddTraits(isMarkedSelected ? .isSelected : [])
        .accessibilityActions { selectAction }
    }
}

/// An icon with its name below, truncated to one line, and an optional second line.
struct TileLabel<Icon: View>: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    /// True for a folder drop target.
    let isHighlighted: Bool
    /// The tile's mark in edit mode, or nil outside it.
    let editMark: EditMark?
    /// Selects the tile from its edit mode badge.
    let onBadgeTap: (@MainActor () -> Void)?
    let style: TileStyle
    let icon: Icon

    @Environment(\.colorSchemeContrast) private var contrast

    init(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        isHighlighted: Bool = false,
        editMark: EditMark? = nil,
        onBadgeTap: (@MainActor () -> Void)? = nil,
        style: TileStyle,
        @ViewBuilder icon: () -> Icon
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
        self.editMark = editMark
        self.onBadgeTap = onBadgeTap
        self.style = style
        self.icon = icon()
    }

    var body: some View {
        let isHighContrast = contrast == .increased
        VStack(spacing: style.labelSpacing) {
            icon
                .frame(width: style.iconSize, height: style.iconSize)
                .overlay(alignment: .topLeading) {
                    if let editMark {
                        EditBadge(mark: editMark, iconSize: style.iconSize) { onBadgeTap?() }
                    }
                }
            // The shadow is on the text only: a shadow of every icon is the costliest part of a moving grid.
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: style.labelFontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: style.labelFontSize * 0.85))
                        .foregroundStyle(.white.opacity(isHighContrast ? 0.95 : 0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .shadow(color: .black.opacity(isHighContrast ? 0.9 : 0.45), radius: isHighContrast ? 3 : 2, y: 1)
        }
        .padding(.horizontal, style.labelInset)
        .padding(.vertical, style.padding)
        .frame(width: style.width)
        .background {
            if let fill = highlight(isHighContrast: isHighContrast) {
                RoundedRectangle(cornerRadius: style.iconSize * 0.2, style: .continuous)
                    .fill(fill)
                    .overlay {
                        if isHighContrast {
                            RoundedRectangle(cornerRadius: style.iconSize * 0.2, style: .continuous)
                                .strokeBorder(.white, lineWidth: 2)
                        }
                    }
            }
        }
        // The selection shows at once, also when it moves along with an animated page turn.
        .animation(nil, value: isSelected)
        .animation(nil, value: editMark)
        .contentShape(Rectangle())
    }

    /// The tile's background: the accent color for an item selected in edit mode, white for the keyboard
    /// selection and a folder drop target, none otherwise.
    private func highlight(isHighContrast: Bool) -> Color? {
        if editMark == .selected {
            return Color.accentColor.opacity(isHighContrast ? 0.55 : 0.35)
        }
        if isSelected || isHighlighted {
            return .white.opacity(isHighContrast ? 0.3 : 0.2)
        }
        return nil
    }
}

/// Darkens a tile while it is pressed.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.25 : 0)
    }
}

/// The tile that follows the pointer during a drag. Where a drop would put the item back, it fades and shows the
/// system's prohibition mark on its icon.
struct DraggedTileView: View {
    let item: Item
    /// True when a drop where the tile is now would put the item back, as over a page with no room.
    let isDropRefused: Bool
    let style: TileStyle
    let store: LayoutStore
    let icons: IconProvider

    var body: some View {
        tile
            .opacity(isDropRefused ? 0.5 : 0.95)
            .overlay(alignment: .top) {
                if isDropRefused, let mark = icons.prohibitionMark {
                    prohibition(mark)
                }
            }
            .scaleEffect(1.08)
            .animation(.easeOut(duration: 0.12), value: isDropRefused)
    }

    @ViewBuilder
    private var tile: some View {
        switch item {
        case .app(let id):
            if let app = store.app(for: id) {
                TileLabel(title: app.displayName, subtitle: nil, isSelected: false, style: style) {
                    Image(nsImage: icons.icon(for: app, side: style.iconSize))
                        .resizable()
                        .interpolation(.high)
                }
            }
        case .folder(let folder):
            TileLabel(title: folder.name, subtitle: nil, isSelected: false, style: style) {
                FolderIcon(apps: folder.apps.compactMap { store.app(for: $0) }, icons: icons)
            }
        }
    }

    /// The mark, unfaded, centered on the corner of the icon's artwork, where the edit mode badge sits. App icons
    /// leave about a tenth of their size clear around the artwork.
    private func prohibition(_ mark: NSImage) -> some View {
        let size = style.iconSize * 0.4
        // The overlay starts centered at the top of the tile. The icon is centered too, `style.padding` below the top.
        return Image(nsImage: mark)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .offset(x: -style.iconSize * 0.4, y: style.padding + style.iconSize * 0.1 - size / 2)
            .accessibilityHidden(true)
    }
}

/// A folder's icon: a translucent rounded square with up to nine of its apps' icons.
struct FolderIcon: View {
    let apps: [InstalledApp]
    let icons: IconProvider

    /// The size of the small icons inside a folder icon of `side` points.
    static func miniSide(forSide side: CGFloat) -> CGFloat {
        (side - side * 0.07 * 4) / 3
    }

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            let spacing = side * 0.07
            let miniSide = Self.miniSide(forSide: side)
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                .fill(.white.opacity(0.22))
                .overlay(alignment: .topLeading) {
                    ForEach(Array(apps.prefix(9).enumerated()), id: \.element.id) { index, app in
                        Image(nsImage: icons.icon(for: app, side: miniSide))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: miniSide, height: miniSide)
                            .offset(
                                x: spacing + CGFloat(index % 3) * (miniSide + spacing),
                                y: spacing + CGFloat(index / 3) * (miniSide + spacing)
                            )
                    }
                }
        }
    }
}
