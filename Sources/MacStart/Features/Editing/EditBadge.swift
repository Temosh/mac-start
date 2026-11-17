import SwiftUI

/// A tile's mark in edit mode.
enum EditMark: Equatable {
    case unselected
    case selected
}

/// The round mark on a tile's icon in edit mode: empty, or a checkmark when the tile is selected, so the selection
/// never shows by color alone. A click on it selects the tile, which is how a folder gets selected, because a click
/// elsewhere on a folder opens it.
struct EditBadge: View {
    let mark: EditMark
    let iconSize: CGFloat
    let onTap: @MainActor () -> Void

    var body: some View {
        let size = max(iconSize * 0.22, 16)
        // App icons leave about a tenth of their size clear around the artwork. The badge sits on its corner.
        let offset = iconSize * 0.1 - size / 2
        ZStack {
            Circle()
                .fill(mark == .selected ? Color.accentColor : Color.black.opacity(0.35))
            Circle()
                .strokeBorder(.white, lineWidth: max(size * 0.08, 1.5))
            if mark == .selected {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        // A little larger than the badge, so it is easy to hit.
        .contentShape(Circle().inset(by: -size * 0.3))
        .highPriorityGesture(TapGesture().onEnded { onTap() })
        .offset(x: offset, y: offset)
        .accessibilityHidden(true)
    }
}
