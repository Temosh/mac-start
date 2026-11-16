import MacStartCore
import SwiftUI

/// One grid slot: an app that launches on click, or a folder.
struct GridItemView: View {
    let item: Item
    /// True when the keyboard selection is on this slot.
    let isSelected: Bool
    let metrics: GridMetrics
    let store: LayoutStore
    let icons: IconProvider
    let actions: OverlayActions

    var body: some View {
        switch item {
        case .app(let id):
            if let app = store.app(for: id) {
                appTile(app)
            }
        case .folder(let folder):
            TileLabel(title: folder.name, subtitle: nil, isSelected: isSelected, metrics: metrics) {
                FolderIcon(apps: folder.apps.compactMap { store.app(for: $0) }, icons: icons)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(folder.name) folder")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }
    }

    private func appTile(_ app: InstalledApp) -> some View {
        // Apps that share a name show their version, so they can be told apart.
        let subtitle = store.sharedDisplayNames.contains(app.displayName) ? app.version : nil
        return Button {
            actions.launch(app)
        } label: {
            TileLabel(title: app.displayName, subtitle: subtitle, isSelected: isSelected, metrics: metrics) {
                Image(nsImage: icons.icon(for: app))
                    .resizable()
                    .interpolation(.high)
            }
        }
        .buttonStyle(TileButtonStyle())
        .focusEffectDisabled()
        .accessibilityLabel(subtitle.map { "\(app.displayName), version \($0)" } ?? app.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// An icon with its name below, truncated to one line, and an optional second line.
struct TileLabel<Icon: View>: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let metrics: GridMetrics
    let icon: Icon

    @Environment(\.colorSchemeContrast) private var contrast

    init(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        metrics: GridMetrics,
        @ViewBuilder icon: () -> Icon
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.metrics = metrics
        self.icon = icon()
    }

    var body: some View {
        let isHighContrast = contrast == .increased
        VStack(spacing: metrics.iconSize * 0.06) {
            icon
                .frame(width: metrics.iconSize, height: metrics.iconSize)
            Text(title)
                .font(.system(size: metrics.labelFontSize, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: metrics.labelFontSize * 0.85))
                    .foregroundStyle(.white.opacity(isHighContrast ? 0.95 : 0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: metrics.cellSize.width * 0.92)
        .shadow(color: .black.opacity(isHighContrast ? 0.9 : 0.45), radius: isHighContrast ? 3 : 2, y: 1)
        .padding(metrics.iconSize * 0.1)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: metrics.iconSize * 0.2, style: .continuous)
                    .fill(.white.opacity(isHighContrast ? 0.3 : 0.2))
                    .overlay {
                        if isHighContrast {
                            RoundedRectangle(cornerRadius: metrics.iconSize * 0.2, style: .continuous)
                                .strokeBorder(.white, lineWidth: 2)
                        }
                    }
            }
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
