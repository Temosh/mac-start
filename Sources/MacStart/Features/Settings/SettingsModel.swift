import AppKit
import Carbon.HIToolbox
import MacStartCore
import Observation
import UniformTypeIdentifiers
import os

/// Applies settings together with their side effects: the global hotkey, launch at login, and backup files.
@MainActor
@Observable
final class SettingsModel {
    let store: LayoutStore
    /// True while the shortcut recorder waits for the new shortcut.
    private(set) var isRecordingHotKey = false
    /// Why the last shortcut could not be used.
    private(set) var hotKeyMessage: String?
    /// What launch at login needs from the user, or why it failed.
    private(set) var loginItemMessage: String?
    /// True when the user has to allow the login item in System Settings.
    private(set) var loginItemNeedsApproval = false

    @ObservationIgnored private let hotKey: GlobalHotKey
    @ObservationIgnored private let loginItem: LoginItem
    @ObservationIgnored private var recordingMonitor: Any?
    @ObservationIgnored private let logger = LogArea.hotkey.logger

    init(store: LayoutStore, hotKey: GlobalHotKey, loginItem: LoginItem) {
        self.store = store
        self.hotKey = hotKey
        self.loginItem = loginItem
    }

    // MARK: - Shortcut

    var hotKeyText: String {
        KeyNames.text(for: store.preferences.hotKey)
    }

    /// Registers the saved shortcut. Runs at launch.
    func registerSavedHotKey() {
        register(store.preferences.hotKey)
    }

    /// Waits for the next key press and makes it the shortcut. Escape cancels.
    func startRecordingHotKey() {
        guard !isRecordingHotKey else {
            return
        }
        isRecordingHotKey = true
        hotKeyMessage = nil
        // The current shortcut must not fire while the user presses the new one.
        hotKey.unregister()
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            // Local monitors run on the main thread.
            MainActor.assumeIsolated {
                self?.record(keyCode: keyCode, modifiers: KeyNames.modifiers(of: flags))
            }
            return nil
        }
    }

    /// Stops waiting for a shortcut and keeps the saved one.
    func cancelRecordingHotKey() {
        guard isRecordingHotKey else {
            return
        }
        endRecording()
        register(store.preferences.hotKey)
    }

    private func record(keyCode: UInt16, modifiers: HotKey.Modifiers) {
        if Int(keyCode) == kVK_Escape, modifiers.isEmpty {
            cancelRecordingHotKey()
            return
        }
        let candidate = HotKey(keyCode: keyCode, modifiers: modifiers)
        guard candidate.isUsableAsGlobalShortcut else {
            hotKeyMessage = "Use Command, Option, or Control with the key, or a function key."
            return
        }
        endRecording()
        do {
            try hotKey.register(candidate)
            store.updatePreferences { $0.hotKey = candidate }
            hotKeyMessage = nil
        } catch {
            hotKeyMessage = "\(KeyNames.text(for: candidate)) is already taken by another app. Choose another shortcut."
            register(store.preferences.hotKey)
        }
    }

    private func endRecording() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
        isRecordingHotKey = false
    }

    private func register(_ shortcut: HotKey) {
        do {
            try hotKey.register(shortcut)
        } catch {
            logger.error("Cannot register the hotkey: \(String(describing: error))")
            hotKeyMessage = "\(KeyNames.text(for: shortcut)) is already taken by another app. Choose another shortcut."
        }
    }

    // MARK: - Grid

    var gridSize: GridSize {
        GridSize(columns: store.preferences.gridColumns, rows: store.preferences.gridRows)
    }

    /// Asks to confirm, then changes the grid size, because the change moves apps the user arranged. Called from
    /// the size pop-up, so the alert waits until the pop-up's own event is done.
    func requestGridSize(_ size: GridSize) {
        guard size != gridSize else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.confirmGridChange(to: size) else {
                return
            }
            self.store.updatePreferences { preferences in
                preferences.gridColumns = size.columns
                preferences.gridRows = size.rows
            }
        }
    }

    private func confirmGridChange(to size: GridSize) -> Bool {
        let current = gridSize
        let alert = NSAlert()
        alert.messageText = "Change the grid to \(size.text)?"
        var details = "Apps keep their order, but they shift into the new rows and columns"
        if size.capacity < current.capacity {
            details += ", and apps that no longer fit move onto the next pages"
        }
        alert.informativeText =
            "Pages hold \(size.capacity) apps instead of \(current.capacity). \(details). Folders and hidden apps stay. "
            + "Changing back does not restore the current arrangement, so export a backup first to keep it."
        alert.addButton(withTitle: "Change Grid")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ isEnabled: Bool) {
        store.updatePreferences { $0.launchAtLogin = isEnabled }
        applyLaunchAtLogin()
    }

    /// Makes the login item match the preference. Runs at every launch, because each ad hoc signed build can
    /// invalidate the previous registration.
    func applyLaunchAtLogin() {
        let isEnabled = store.preferences.launchAtLogin
        do {
            try loginItem.setEnabled(isEnabled)
            loginItemNeedsApproval = isEnabled && loginItem.status == .requiresApproval
            loginItemMessage = loginItemNeedsApproval ? "Allow MacStart in System Settings to open it at login." : nil
        } catch {
            LogArea.overlay.logger.error("Cannot change launch at login: \(String(describing: error))")
            loginItemNeedsApproval = false
            loginItemMessage = "Cannot change launch at login: \(error.localizedDescription)"
        }
    }

    func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }

    // MARK: - Hidden apps

    /// A hidden app, which may no longer be installed.
    struct HiddenApp: Identifiable {
        let id: AppID
        /// Nil when the app is not installed.
        let app: InstalledApp?

        var name: String {
            app?.displayName ?? URL(filePath: id.path).deletingPathExtension().lastPathComponent
        }
    }

    /// The hidden apps, by name.
    var hiddenApps: [HiddenApp] {
        store.layout.hidden
            .map { HiddenApp(id: $0, app: store.app(for: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func unhide(_ ids: Set<AppID>) {
        store.unhide(ids)
    }

    // MARK: - Reset

    /// Asks to confirm, then starts the layout over from the installed apps.
    func resetLayout() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Reset the layout?"
        alert.informativeText =
            "Every app goes back in name order, folders are removed, and hidden apps show again. Settings stay. "
            + "This cannot be undone, so export a backup first to keep the current layout."
        alert.addButton(withTitle: "Reset Layout").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        store.resetLayout()
    }

    // MARK: - Backup

    /// Asks where to save, then writes the layout and every preference to one JSON file.
    func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "MacStart Backup \(Date.now.formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        let export = store.makeExport()
        Task {
            do {
                try await Self.write(try export.jsonData(), to: url)
            } catch {
                showAlert(title: "Cannot save the backup", message: error.localizedDescription)
            }
        }
    }

    /// Asks for a backup file, checks it, asks to confirm, then replaces the layout and the preferences.
    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        Task {
            let export: Export
            do {
                export = try Export(jsonData: try await Self.read(from: url))
            } catch {
                showAlert(title: "Cannot import “\(url.lastPathComponent)”", message: Self.importFailureReason(error))
                return
            }
            guard confirmReplacing(with: export) else {
                return
            }
            store.applyImport(export)
            register(store.preferences.hotKey)
            applyLaunchAtLogin()
        }
    }

    private func confirmReplacing(with export: Export) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace the current layout and settings?"
        alert.informativeText =
            "The backup from \(export.exportedAt.formatted(date: .long, time: .shortened)) replaces the pages, "
            + "folders, hidden apps, and every setting. This cannot be undone."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// A reason for the user, with what to do about it when there is something to do.
    static func importFailureReason(_ error: any Error) -> String {
        switch error as? PersistenceError {
        case .unsupportedSchemaVersion(let found, let supported)?:
            if found > supported {
                return "This backup comes from a newer version of MacStart (format \(found)). "
                    + "This version reads format \(supported). Update MacStart, then import again."
            }
            return "This backup uses format \(found), which this version of MacStart cannot read."
        case .malformedData?:
            return "The file is not a MacStart backup, or it is damaged."
        case nil:
            return error.localizedDescription
        }
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @concurrent
    private nonisolated static func write(_ data: Data, to url: URL) async throws {
        try data.write(to: url, options: .atomic)
    }

    @concurrent
    private nonisolated static func read(from url: URL) async throws -> Data {
        try Data(contentsOf: url)
    }
}

/// A grid size Settings offers: every allowed column count for every allowed row count.
struct GridSize: Hashable {
    let columns: Int
    let rows: Int

    var capacity: Int {
        columns * rows
    }

    /// Columns by rows, as in "7 × 5".
    var text: String {
        "\(columns) × \(rows)"
    }
}
