import SwiftUI

/// The open folder's panel grows out of the folder's icon, as in Launchpad. A folder that is not on the shown page has
/// no icon to grow from, so its panel grows a little from where it stands. A closing panel shrinks with `effect`.
struct FolderZoom: Transition {
    /// The center of the folder's icon, in overlay coordinates, or nil when the icon is not on the shown page.
    let iconCenter: CGPoint?
    let iconSize: CGFloat
    /// The panel, in overlay coordinates.
    let panel: CGRect
    let overlaySize: CGSize

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(effect(isCollapsed: !phase.isIdentity))
    }

    /// The panel shrunk into the icon, or at full size. A closing panel uses it to shrink while it stays in place.
    func effect(isCollapsed: Bool) -> Effect {
        Effect(zoom: self, isCollapsed: isCollapsed)
    }

    struct Effect: ViewModifier {
        let zoom: FolderZoom
        let isCollapsed: Bool

        func body(content: Content) -> some View {
            content
                .scaleEffect(isCollapsed ? zoom.collapsedScale : 1, anchor: zoom.panelCenter)
                .offset(isCollapsed ? zoom.collapsedOffset : .zero)
                .opacity(isCollapsed ? 0 : 1)
        }
    }

    /// The panel as wide as the icon.
    private var collapsedScale: CGFloat {
        guard iconCenter != nil else {
            return 0.9
        }
        return iconSize / max(panel.width, 1)
    }

    /// The panel's center, as a point of the panel view, which covers the whole overlay.
    private var panelCenter: UnitPoint {
        UnitPoint(x: panel.midX / max(overlaySize.width, 1), y: panel.midY / max(overlaySize.height, 1))
    }

    /// From the panel's center to the icon's center.
    private var collapsedOffset: CGSize {
        guard let iconCenter else {
            return .zero
        }
        return CGSize(width: iconCenter.x - panel.midX, height: iconCenter.y - panel.midY)
    }
}
