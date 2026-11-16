import AppKit
import Carbon.HIToolbox
import MacStartCore
import SwiftUI
import os

/// Shows and hides the overlay, and turns the user's actions in it into launches, page changes, and dismissals.
@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    /// The length of the show and hide animations, in seconds.
    static let animationDuration = 0.2
    /// The shortest time between two page turns from a mouse wheel, so one flick turns one page.
    private static let wheelPageTurnInterval = 0.3

    let state = OverlayState()
    private let store: LayoutStore
    private let icons: IconProvider
    private let launcher: AppLauncher
    private lazy var panel = makePanel()
    /// Bumped on every show and hide, so a hide that finishes late cannot close a panel shown again meanwhile.
    private var visibilityGeneration = 0
    private var scrollMonitor: Any?
    private var lastWheelPageTurn = Date.distantPast
    /// The last app other than MacStart that was active. It gets the focus back when the overlay closes while
    /// MacStart is active, for example after a click on the Dock icon.
    private var previousApp: NSRunningApplication?
    private let logger = LogArea.overlay.logger

    init(store: LayoutStore, icons: IconProvider, launcher: AppLauncher) {
        self.store = store
        self.icons = icons
        self.launcher = launcher
        super.init()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func toggle() {
        if state.isPresented {
            hide()
        } else {
            show()
        }
    }

    /// Shows the overlay on the main display, the one with the menu bar.
    func show() {
        guard let screen = NSScreen.screens.first else {
            logger.error("No display to show the overlay on")
            return
        }
        visibilityGeneration += 1
        panel.setFrame(screen.frame, display: false)
        state.clampPage(toPageCount: store.layout.pages.count)

        if !panel.isVisible {
            panel.contentView?.alphaValue = 0
        }
        panel.makeKeyAndOrderFront(nil)
        state.isPresented = true
        fadeContent(toVisible: true)
        installScrollMonitor()
        logger.debug(
            "Overlay shown, frame \(NSStringFromRect(self.panel.frame), privacy: .public), screen \(NSStringFromRect(screen.frame), privacy: .public)"
        )
    }

    /// Hides the overlay. With `restoringFocus`, the previous app gets the focus back if MacStart took it.
    func hide(restoringFocus: Bool = true) {
        guard state.isPresented else {
            return
        }
        state.isPresented = false
        removeScrollMonitor()
        visibilityGeneration += 1
        let generation = visibilityGeneration

        fadeContent(toVisible: false)
        guard !Self.reduceMotion else {
            finishHiding(generation: generation, restoringFocus: restoringFocus)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(Self.animationDuration))
            finishHiding(generation: generation, restoringFocus: restoringFocus)
        }
        logger.debug("Overlay hiding, restoring focus: \(restoringFocus)")
    }

    private func finishHiding(generation: Int, restoringFocus: Bool) {
        guard generation == visibilityGeneration else {
            return
        }
        panel.orderOut(nil)
        logger.debug("Overlay ordered out")
        if restoringFocus, NSApp.isActive {
            previousApp?.activate()
        }
    }

    /// Fades the panel's content in or out. The final opacity is set first and the fade only animates the way
    /// there, so the overlay ends up right even when no animation runs, for example while the display sleeps.
    /// The window's own alpha is never animated: `NSWindow.animator()` can leave it stuck at the start value.
    private func fadeContent(toVisible isVisible: Bool) {
        guard let content = panel.contentView else {
            return
        }
        let target: CGFloat = isVisible ? 1 : 0
        let start = content.layer?.presentation()?.opacity ?? Float(content.alphaValue)
        content.alphaValue = target
        guard !Self.reduceMotion, let layer = content.layer else {
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = start
        fade.toValue = Float(target)
        fade.duration = Self.animationDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "fade")
    }

    /// Scrolls to a page, clamped to the existing pages.
    func showPage(_ index: Int) {
        let pageCount = store.layout.pages.count
        guard pageCount > 0 else {
            return
        }
        let page = min(max(index, 0), pageCount - 1)
        withAnimation(Self.reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            state.currentPage = page
        }
    }

    private func turnPage(by offset: Int) {
        showPage((state.currentPage ?? 0) + offset)
    }

    private func launch(_ app: InstalledApp) {
        hide(restoringFocus: false)
        Task {
            do {
                try await launcher.launch(app)
            } catch {
                presentLaunchFailure(of: app, error: error)
            }
        }
    }

    private func presentLaunchFailure(of app: InstalledApp, error: any Error) {
        logger.error("Cannot open \(app.id.path): \(String(describing: error))")
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Cannot open \(app.displayName)"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    // MARK: - Input

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Escape:
            hide()
            return true
        case kVK_LeftArrow:
            turnPage(by: -1)
            return true
        case kVK_RightArrow:
            turnPage(by: 1)
            return true
        default:
            // Swallow other plain keys so the panel does not beep. Command shortcuts go on to the menus.
            return !event.modifierFlags.contains(.command)
        }
    }

    /// Turns pages with a mouse wheel. Trackpads and the Magic Mouse scroll precisely, and the paged scroll view
    /// handles their swipes itself.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else {
            return
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard !event.hasPreciseScrollingDeltas else {
                return event
            }
            let delta =
                abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
            guard delta != 0 else {
                return event
            }
            // Local monitors run on the main thread.
            MainActor.assumeIsolated { self?.turnPageForWheel(delta: delta) }
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    private func turnPageForWheel(delta: CGFloat) {
        let now = Date.now
        guard now.timeIntervalSince(lastWheelPageTurn) >= Self.wheelPageTurnInterval else {
            return
        }
        lastWheelPageTurn = now
        turnPage(by: delta < 0 ? 1 : -1)
    }

    // MARK: - Window and system events

    func windowDidResignKey(_ notification: Notification) {
        // Another app or window took the focus.
        logger.debug("Overlay lost key focus")
        hide()
    }

    @objc private func activeSpaceDidChange() {
        logger.debug("Active Space changed")
        hide()
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return
        }
        previousApp = app
    }

    @objc private func screenParametersDidChange() {
        if state.isPresented, let screen = NSScreen.screens.first {
            panel.setFrame(screen.frame, display: true)
        }
    }

    // MARK: - Setup

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(contentRect: NSScreen.screens.first?.frame ?? .zero)
        panel.delegate = self
        panel.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        let actions = OverlayActions(
            launch: { [weak self] app in self?.launch(app) },
            dismiss: { [weak self] in self?.hide() },
            showPage: { [weak self] page in self?.showPage(page) }
        )
        panel.setContent(OverlayView(store: store, state: state, icons: icons, actions: actions))
        return panel
    }
}
