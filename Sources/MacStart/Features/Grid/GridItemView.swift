import MacStartCore
import SwiftUI

/// One tile: an app that launches on click, or a folder that opens on click. Tiles carry no drag gesture: the
/// overlay has one for all of them.
struct GridItemView: View {
    let item: Item
    /// True when the keyboard selection is on this tile.
    let isSelected: Bool
    /// True while a dragged app rests on this tile, so a drop here makes or fills a folder.
    let isFolderTarget: Bool
    let style: TileStyle
    /// Where the tile sits, for the context menu. Nil for search results.
    let location: LayoutLocation?
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
            actions.launch(app)
        } label: {
            TileLabel(
                title: app.displayName,
                subtitle: subtitle,
                isSelected: isSelected,
                isHighlighted: isFolderTarget,
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
            Button("Hide") {
                actions.hide(app)
            }
            Button("Show in Finder") {
                actions.showInFinder(app)
            }
            if case .inFolder(let folderID, let index)? = location {
                Button("Remove from Folder") {
                    actions.removeFromFolder(folderID, index)
                }
            }
        }
        .accessibilityLabel(subtitle.map { "\(app.displayName), version \($0)" } ?? app.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func folderTile(_ folder: Folder) -> some View {
        Button {
            actions.openFolder(folder.id)
        } label: {
            TileLabel(
                title: folder.name,
                subtitle: nil,
                isSelected: isSelected,
                isHighlighted: isFolderTarget,
                style: style
            ) {
                FolderIcon(apps: folder.apps.compactMap { store.app(for: $0) }, icons: icons)
            }
        }
        .buttonStyle(TileButtonStyle())
        .focusEffectDisabled()
        .accessibilityLabel("\(folder.name) folder")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// An icon with its name below, truncated to one line, and an optional second line.
struct TileLabel<Icon: View>: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    /// True for a folder drop target.
    let isHighlighted: Bool
    let style: TileStyle
    let icon: Icon

    @Environment(\.colorSchemeContrast) private var contrast

    init(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        isHighlighted: Bool = false,
        style: TileStyle,
        @ViewBuilder icon: () -> Icon
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
        self.style = style
        self.icon = icon()
    }

    var body: some View {
        let isHighContrast = contrast == .increased
        VStack(spacing: style.labelSpacing) {
            icon
                .frame(width: style.iconSize, height: style.iconSize)
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
        .frame(maxWidth: style.maxLabelWidth)
        .padding(style.padding)
        .background {
            if isSelected || isHighlighted {
                RoundedRectangle(cornerRadius: style.iconSize * 0.2, style: .continuous)
                    .fill(.white.opacity(isHighContrast ? 0.3 : 0.2))
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
        .contentShape(Rectangle())
    }
}

/// Darkens a tile while it is pressed.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.25 : 0)
    }
}

/// The tile that follows the pointer during a drag.
struct DraggedTileView: View {
    let item: Item
    let style: TileStyle
    let store: LayoutStore
    let icons: IconProvider

    var body: some View {
        Group {
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
        .scaleEffect(1.08)
        .opacity(0.95)
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
