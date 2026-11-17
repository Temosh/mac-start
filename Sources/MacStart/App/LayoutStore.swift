import Foundation
import MacStartCore
import Observation
import os

/// Owns the single mutable `Layout`, the current catalog, and the preferences. Every layout change goes through
/// this store on the main actor. Scans and file I/O run off the main actor.
@MainActor
@Observable
final class LayoutStore {
    private(set) var layout = Layout.empty
    private(set) var catalog = Catalog.empty
    private(set) var preferences: Preferences
    /// False until the first catalog scan is reconciled, so the overlay never shows a half-loaded grid.
    private(set) var hasLoaded = false
    /// Display names that several installed apps share. These apps show their version under the name.
    private(set) var sharedDisplayNames: Set<String> = []

    @ObservationIgnored private let scanner: CatalogScanner
    @ObservationIgnored private let fileStore: LayoutFileStore
    @ObservationIgnored private let preferencesStore: PreferencesStore
    @ObservationIgnored private let writer: LayoutWriter
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var isScanPending = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private let logger = LogArea.layout.logger

    init(
        scanner: CatalogScanner,
        fileStore: LayoutFileStore,
        preferencesStore: PreferencesStore,
        preferences: Preferences
    ) {
        self.scanner = scanner
        self.fileStore = fileStore
        self.preferencesStore = preferencesStore
        self.preferences = preferences
        writer = LayoutWriter(fileStore: fileStore)
    }

    /// The installed app for a placed ID, or nil while the catalog does not know it.
    func app(for id: AppID) -> InstalledApp? {
        catalog[id]
    }

    /// Search results for the overlay: at most one page of the best matches.
    func searchResults(matching query: String) -> [InstalledApp] {
        Array(layout.searchResults(matching: query, in: catalog).prefix(preferences.pageCapacity))
    }

    /// The folder with `id`, if it still exists.
    func folder(withID id: UUID) -> Folder? {
        guard let position = layout.position(ofFolder: id),
            case .folder(let folder) = layout.pages[position.page].items[position.slot]
        else {
            return nil
        }
        return folder
    }

    // MARK: - Editing

    /// Moves the item at `source` to `destination`. See `Layout.moveItem(from:to:pageCapacity:)`.
    func moveItem(from source: LayoutLocation, to destination: GridPosition) {
        edit { $0.moveItem(from: source, to: destination, pageCapacity: preferences.pageCapacity) }
    }

    /// Drops the app at `source` onto the item at `target`, making or joining a folder. A new folder is named
    /// after the apps' App Store category. Returns the folder's identifier.
    @discardableResult
    func dropApp(from source: LayoutLocation, onto target: GridPosition) -> UUID? {
        var folderID: UUID?
        edit { layout in
            folderID = layout.dropApp(
                from: source,
                onto: target,
                newFolderName: { targetID, droppedID in
                    Folder.defaultName(target: self.catalog[targetID], dropped: self.catalog[droppedID])
                },
                pageCapacity: preferences.pageCapacity
            )
        }
        return folderID
    }

    /// Moves an app out of its folder into the slot after the folder.
    func removeApp(fromFolder id: UUID, at index: Int) {
        edit { $0.removeApp(fromFolder: id, at: index, pageCapacity: preferences.pageCapacity) }
    }

    /// Moves several apps out of a folder, into the slots right after it.
    func removeApps(_ apps: Set<AppID>, fromFolder id: UUID) {
        edit { $0.removeApps(apps, fromFolder: id, pageCapacity: preferences.pageCapacity) }
    }

    /// Reorders an app inside its folder.
    func moveApp(inFolder id: UUID, from index: Int, to destination: Int) {
        edit { $0.moveApp(inFolder: id, from: index, to: destination) }
    }

    /// Hides an app from the grid and from search.
    func hide(_ id: AppID) {
        edit { $0.hide(id) }
    }

    /// Starts the layout over, as on the first launch: every installed app in name order, with no folders and no
    /// hidden apps. The preferences stay.
    func resetLayout() {
        edit { $0 = .empty }
        logger.info("Reset the layout to \(self.layout.placedAppIDs.count) apps in name order")
    }

    /// Hides several apps at once.
    func hide(_ ids: Set<AppID>) {
        edit { layout in
            for id in ids {
                layout.hide(id)
            }
        }
    }

    /// Moves items to the end of `page`, in reading order. See `Layout.moveItems(_:toPage:pageCapacity:)`.
    func moveItems(_ ids: Set<Item.ID>, toPage page: Int) {
        edit { $0.moveItems(ids, toPage: page, pageCapacity: preferences.pageCapacity) }
    }

    /// Makes a folder of the apps where the first of them is, named after the first App Store category among
    /// them. Returns the folder's identifier.
    @discardableResult
    func makeFolder(of apps: Set<AppID>) -> UUID? {
        var folderID: UUID?
        edit { layout in
            folderID = layout.makeFolder(
                of: apps,
                named: { ids in Folder.defaultName(for: ids.compactMap { self.catalog[$0] }) },
                pageCapacity: preferences.pageCapacity
            )
        }
        return folderID
    }

    /// Shows a hidden app again, at the end of the last page.
    func unhide(_ id: AppID) {
        edit { $0.unhide(id) }
    }

    // MARK: - Preferences, export, and import

    /// Changes and saves the preferences. A new grid size reflows the pages at once.
    func updatePreferences(_ change: (inout Preferences) -> Void) {
        var updated = preferences
        change(&updated)
        guard updated != preferences else {
            return
        }
        let capacityChanged = updated.pageCapacity != preferences.pageCapacity
        preferences = updated
        savePreferences()
        if capacityChanged {
            edit { _ in }
        }
    }

    /// The current layout and preferences, ready to write to an export file.
    func makeExport() -> Export {
        Export.snapshot(layout: layout, preferences: preferences)
    }

    /// Replaces the layout and the preferences with an import. Apps missing on this Mac leave the grid but stay
    /// hidden when they were hidden.
    func applyImport(_ export: Export) {
        preferences = export.preferences
        savePreferences()
        layout = export.layout.reconciled(with: catalog, pageCapacity: preferences.pageCapacity)
        save()
        logger.info("Imported a layout with \(self.layout.placedAppIDs.count) placed apps")
    }

    /// Writes the preferences to `UserDefaults`.
    func savePreferences() {
        do {
            try preferencesStore.save(preferences)
        } catch {
            logger.error("Cannot save the preferences: \(String(describing: error))")
        }
    }

    func renameFolder(_ id: UUID, to name: String) {
        edit { $0.renameFolder(id, to: name) }
    }

    /// Applies an edit, reconciles the result so every invariant holds, and saves it when it changed.
    private func edit(_ change: (inout Layout) -> Void) {
        var edited = layout
        change(&edited)
        let reconciled = edited.reconciled(with: catalog, pageCapacity: preferences.pageCapacity)
        guard reconciled != layout else {
            return
        }
        layout = reconciled
        save()
    }

    /// Reads the stored layout, then scans and reconciles. Call once at launch.
    func load() async {
        if let stored = await Self.readStoredLayout(from: fileStore) {
            layout = stored
        }
        await refreshCatalog()
    }

    /// Scans the app folders and reconciles the layout with the result. A call that arrives during a scan
    /// schedules one more scan, so the last change is never missed.
    func refreshCatalog() async {
        guard !isScanning else {
            isScanPending = true
            return
        }
        isScanning = true
        defer { isScanning = false }
        repeat {
            isScanPending = false
            apply(catalog: await Self.scan(with: scanner))
        } while isScanPending
    }

    private func apply(catalog newCatalog: Catalog) {
        let reconciled = layout.reconciled(with: newCatalog, pageCapacity: preferences.pageCapacity)
        catalog = newCatalog
        sharedDisplayNames = newCatalog.sharedDisplayNames
        let isFirstLoad = !hasLoaded
        hasLoaded = true
        guard reconciled != layout || isFirstLoad else {
            return
        }
        layout = reconciled
        save()
    }

    private func save() {
        revision += 1
        let snapshot = layout
        let revision = revision
        Task {
            await writer.write(snapshot, revision: revision)
        }
    }

    @concurrent
    private nonisolated static func scan(with scanner: CatalogScanner) async -> Catalog {
        scanner.scan()
    }

    /// The stored layout, or nil when there is none or it cannot be read. An unreadable file is renamed, so the
    /// next save does not destroy it.
    @concurrent
    private nonisolated static func readStoredLayout(from fileStore: LayoutFileStore) async -> Layout? {
        let logger = LogArea.layout.logger
        do {
            return try fileStore.load()
        } catch {
            logger.error("Cannot read the stored layout: \(String(describing: error))")
            do {
                let backup = try fileStore.moveUnreadableFileAside()
                logger.notice("Moved the unreadable layout to \(backup.path(percentEncoded: false))")
            } catch {
                logger.error("Cannot move the unreadable layout aside: \(String(describing: error))")
            }
            return nil
        }
    }
}

/// Writes layouts to disk one at a time, off the main actor, and drops writes older than the last one written.
actor LayoutWriter {
    private let fileStore: LayoutFileStore
    private var lastWrittenRevision = 0
    private let logger = LogArea.layout.logger

    init(fileStore: LayoutFileStore) {
        self.fileStore = fileStore
    }

    func write(_ layout: Layout, revision: Int) {
        guard revision > lastWrittenRevision else {
            return
        }
        do {
            try fileStore.save(layout)
            lastWrittenRevision = revision
        } catch {
            logger.error("Cannot save the layout: \(String(describing: error))")
        }
    }
}
