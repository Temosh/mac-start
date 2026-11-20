import AppKit
import SwiftUI

/// The borderless full-screen panel that hosts the overlay.
///
/// It covers the menu bar and the Dock, opens on the active Space, also over a full-screen app, and stays on that
/// Space. It takes keyboard focus without activating MacStart, so the app the user was in stays active underneath.
final class OverlayPanel: NSPanel {
    /// Shown with full-screen apps, left out of the window cycle, and on one Space only, so the panel never follows
    /// the user to another Space.
    private static let oneSpaceBehavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]

    /// Handles a key press. Returns true when the key was used.
    var onKeyDown: ((NSEvent) -> Bool)?
    /// The SwiftUI content above the blur, which the controller zooms with Core Animation as the overlay shows and
    /// hides.
    private(set) weak var hostingView: NSView?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Above the menu bar and the Dock, below pop-up menus, so context menus still appear on top.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = Self.oneSpaceBehavior
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Launchpad is dark in both appearances; white labels need a dark blur.
        appearance = NSAppearance(named: .darkAqua)
    }

    /// Hosts `rootView` on top of a blur of whatever is behind the panel.
    func setContent(_ rootView: some View) {
        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        // Layer-backed, so the controller can fade the content with Core Animation.
        blur.wantsLayer = true
        contentView = blur

        let hostingView = NSHostingView(rootView: rootView)
        // The panel's frame follows the screen; the SwiftUI content must never resize it.
        hostingView.sizingOptions = []
        // Layer-backed from the start, so the controller can zoom the content before it first draws.
        hostingView.wantsLayer = true
        hostingView.frame = blur.bounds
        hostingView.autoresizingMask = [.width, .height]
        blur.addSubview(hostingView)
        self.hostingView = hostingView
    }

    /// Orders the panel in as the key window on the active Space and keeps it there. Kept on every Space, it also
    /// showed on the new Space during a Space switch, over the wrong wallpaper.
    ///
    /// It orders in while joining every Space, the setup that shows it over full-screen apps, and leaves the other
    /// Spaces right after. Only ordering in moves it to the active Space, so a panel still fading out on a Space the
    /// user left goes out first; otherwise it would stay on that Space.
    func makeKeyAndOrderFrontOnActiveSpace() {
        if isVisible, !isOnActiveSpace {
            orderOut(nil)
        }
        collectionBehavior = Self.oneSpaceBehavior.union(.canJoinAllSpaces)
        makeKeyAndOrderFront(nil)
        collectionBehavior = Self.oneSpaceBehavior
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
}
