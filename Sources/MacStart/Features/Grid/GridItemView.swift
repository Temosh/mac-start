import MacStartCore
import SwiftUI

/// One grid slot: an app that launches on click, or a folder.
struct GridItemView: View {
    let item: Item
    let metrics: GridMetrics
    let store: LayoutStore
    let icons: IconProvider
    let actions: OverlayActions

    var body: some View {
        switch item {
        case .app(let id):
            if let app = store.app(for: id) {
                Button {
                    actions.launch(app)
                } label: {
                    TileLabel(title: app.displayName, metrics: metrics) {
                        Image(nsImage: icons.icon(for: app))
                            .resizable()
                            .interpolation(.high)
                    }
                }
                .buttonStyle(TileButtonStyle())
                .focusEffectDisabled()
            }
        case .folder(let folder):
            TileLabel(title: folder.name, metrics: metrics) {
                FolderIcon(apps: folder.apps.compactMap { store.app(for: $0) }, icons: icons)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// An icon with its name below, truncated to one line.
struct TileLabel<Icon: View>: View {
    let title: String
    let metrics: GridMetrics
    let icon: Icon

    init(title: String, metrics: GridMetrics, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.metrics = metrics
        self.icon = icon()
    }

    var body: some View {
        VStack(spacing: metrics.iconSize * 0.08) {
            icon
                .frame(width: metrics.iconSize, height: metrics.iconSize)
            Text(title)
                .font(.system(size: metrics.labelFontSize, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: metrics.cellSize.width * 0.92)
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        }
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

/// A folder's icon: a translucent rounded square with up to nine of its apps' icons.
struct FolderIcon: View {
    let apps: [InstalledApp]
    let icons: IconProvider

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            let spacing = side * 0.07
            let miniSide = (side - spacing * 4) / 3
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                .fill(.white.opacity(0.22))
                .overlay(alignment: .topLeading) {
                    ForEach(Array(apps.prefix(9).enumerated()), id: \.element.id) { index, app in
                        Image(nsImage: icons.icon(for: app))
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
