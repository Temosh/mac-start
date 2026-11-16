import AppKit
import CoreServices
import MacStartCore

/// Owns app startup and the app-level system callbacks, and wires the parts together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = LogArea.overlay.logger
    /// True when no preferences were saved yet, which marks the first launch.
    private let isFirstLaunch: Bool
    private let store: LayoutStore
    private let icons = IconProvider()
    private lazy var overlay = OverlayController(store: store, icons: icons, launcher: AppLauncher())
    private lazy var hotKey = GlobalHotKey { [weak self] in
        self?.overlay.toggle()
    }
    private lazy var settings = SettingsModel(store: store, hotKey: hotKey, loginItem: LoginItem())
    private lazy var settingsWindow = SettingsWindowController(model: settings, icons: icons)
    private var catalogWatcher: CatalogWatcher?

    override init() {
        let preferencesStore = PreferencesStore()
        let savedPreferences = preferencesStore.load()
        isFirstLaunch = savedPreferences == nil
        store = LayoutStore(
            scanner: CatalogScanner(roots: CatalogScanner.standardRoots()),
            fileStore: LayoutFileStore(fileURL: LayoutFileStore.standardFileURL),
            preferencesStore: preferencesStore,
            preferences: savedPreferences ?? .default
        )
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A Dock icon, like Launchpad. Set in code because an executable started outside
        // its bundle (for example with `swift run`) gets no activation policy from Info.plist.
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = MainMenu.make()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("MacStart launched")
        if isFirstLaunch {
            store.savePreferences()
        }
        settings.registerSavedHotKey()
        // Registers launch at login on the first launch, and again after an update changed the signature.
        settings.applyLaunchAtLogin()
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

    /// The Dock icon's menu adds Settings.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Opens the settings window, from the app menu (Command-Comma) or the Dock icon's menu.
    @objc func openSettings(_ sender: Any?) {
        overlay.hide(restoringFocus: false)
        settingsWindow.show()
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
