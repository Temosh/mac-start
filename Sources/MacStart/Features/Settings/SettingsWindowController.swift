import AppKit
import SwiftUI

/// Hosts the settings in an ordinary window, opened with Command-Comma or from the Dock icon's menu.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private let icons: IconProvider
    private var window: NSWindow?

    init(model: SettingsModel, icons: IconProvider) {
        self.model = model
        self.icons = icons
    }

    /// Shows the window in front, creating it the first time.
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelRecordingHotKey()
    }

    /// Recording stops when the window loses the focus, so the saved shortcut never stays unregistered.
    func windowDidResignKey(_ notification: Notification) {
        model.cancelRecordingHotKey()
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(model: model, icons: icons))
        controller.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: controller)
        window.title = "MacStart Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.center()
        return window
    }
}
