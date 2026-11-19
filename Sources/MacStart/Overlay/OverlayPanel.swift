import AppKit
import SwiftUI

/// The borderless full-screen panel that hosts the overlay.
///
/// It covers the menu bar and the Dock, appears on the active Space and over full-screen apps, and takes keyboard
/// focus without activating MacStart, so the app the user was in stays active underneath.
final class OverlayPanel: NSPanel {
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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
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
