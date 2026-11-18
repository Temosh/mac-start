import AppKit
import SwiftUI

/// Hosts the settings in an ordinary window, opened with Command-Comma or from the Dock icon's menu.
///
/// As Apple's guidelines ask for macOS settings, a toolbar that cannot be customized has one button per pane and
/// always shows the active one, the window's title names the pane, the window takes each pane's size, and its
/// minimize and zoom buttons are dimmed. The window lives as long as the app, so it opens on the last pane used.
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
        let panes = NSTabViewController()
        panes.tabStyle = .toolbar
        addPane("General", symbol: "gearshape", GeneralSettingsPane(model: model), to: panes)
        addPane("Layout", symbol: "square.grid.3x3", LayoutSettingsPane(model: model), to: panes)
        addPane("Hidden Apps", symbol: "eye.slash", HiddenAppsSettingsPane(model: model, icons: icons), to: panes)
        addPane("Backup", symbol: "externaldrive", BackupSettingsPane(model: model), to: panes)
        let window = NSWindow(contentViewController: panes)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.center()
        return window
    }

    private func addPane(_ title: String, symbol: String, _ pane: some View, to panes: NSTabViewController) {
        let controller = NSHostingController(rootView: pane)
        controller.sizingOptions = .preferredContentSize
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        panes.addTabViewItem(item)
    }
}
