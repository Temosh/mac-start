import AppKit
import MacStartCore

/// Owns app startup and the app-level system callbacks.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = LogArea.overlay.logger

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A Dock icon, like Launchpad. Set in code because an executable started outside
        // its bundle (for example with `swift run`) gets no activation policy from Info.plist.
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = MainMenu.make()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("MacStart launched")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
