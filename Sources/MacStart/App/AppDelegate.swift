import AppKit
import CoreServices
import MacStartCore

/// Owns app startup and the app-level system callbacks, and wires the parts together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = LogArea.overlay.logger
    private let store = LayoutStore(
        scanner: CatalogScanner(roots: CatalogScanner.standardRoots()),
        fileStore: LayoutFileStore(fileURL: LayoutFileStore.standardFileURL),
        preferences: PreferencesStore().load() ?? .default
    )
    private lazy var overlay = OverlayController(store: store, icons: IconProvider(), launcher: AppLauncher())
    private var hotKey: GlobalHotKey?
    private var catalogWatcher: CatalogWatcher?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A Dock icon, like Launchpad. Set in code because an executable started outside
        // its bundle (for example with `swift run`) gets no activation policy from Info.plist.
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = MainMenu.make()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("MacStart launched")
        registerHotKey()
        catalogWatcher = CatalogWatcher(roots: CatalogScanner.standardRoots()) { [weak self] in
            guard let self else {
                return
            }
            Task { await self.store.refreshCatalog() }
        }
        Task { await store.load() }
        if !isLaunchedAsLoginItem {
            overlay.show()
        }
    }

    /// A click on the Dock icon toggles the overlay.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlay.toggle()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func registerHotKey() {
        let hotKey = GlobalHotKey { [weak self] in
            self?.overlay.toggle()
        }
        do {
            try hotKey.register(store.preferences.hotKey)
        } catch {
            LogArea.hotkey.logger.error("Cannot register the hotkey: \(String(describing: error))")
        }
        self.hotKey = hotKey
    }

    /// True when macOS started the app at login. The overlay then stays hidden until the user opens it.
    private var isLaunchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
                == OSType(keyAELaunchedAsLogInItem)
    }
}
