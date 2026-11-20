import SwiftUI

/// The open folder's panel grows out of the folder's icon, as in Launchpad, and shrinks back into it when the folder
/// closes. A folder that is not on the shown page has no icon to grow from, so its panel grows a little from where it
/// stands.
@MainActor
struct FolderZoom {
    /// The center of the folder's icon, in overlay coordinates, or nil when the icon is not on the shown page.
    let iconCenter: CGPoint?
    let iconSize: CGFloat
    /// The panel, in overlay coordinates.
    let panel: CGRect
    let overlaySize: CGSize

    /// Zooms the panel in as it appears, and out once `isClosing`.
    func appearance(isClosing: Bool) -> Appearance {
        Appearance(zoom: self, isClosing: isClosing)
    }

    /// Starts the panel shrunk into the icon and zooms it in once it appears. Both zooms run in this one modifier,
    /// so the views inside always know when the panel is zooming: a transition does not tell them.
    struct Appearance: ViewModifier {
        let zoom: FolderZoom
        let isClosing: Bool

        @State private var hasAppeared = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content
                .modifier(Effect(zoom: zoom, progress: hasAppeared && !isClosing ? 1 : 0))
                .onAppear {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: OverlayState.folderZoomDuration)) {
                        hasAppeared = true
                    }
                }
        }
    }

    /// The panel `progress` of the way from shrunk into the icon and clear, at 0, to full size, at 1. In between, it
    /// tells the views inside that the panel is zooming, from the first frame of a zoom to its last.
    struct Effect: ViewModifier, Animatable {
        let zoom: FolderZoom
        nonisolated var progress: CGFloat

        nonisolated var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            content
                .environment(\.isFolderZooming, progress < 1)
                .scaleEffect(zoom.collapsedScale + (1 - zoom.collapsedScale) * progress, anchor: zoom.panelCenter)
                .offset(
                    x: zoom.collapsedOffset.width * (1 - progress),
                    y: zoom.collapsedOffset.height * (1 - progress)
                )
                .opacity(progress)
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

extension EnvironmentValues {
    /// True while the open folder's panel grows or shrinks.
    @Entry var isFolderZooming = false
}
