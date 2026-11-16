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

    @ObservationIgnored private let scanner: CatalogScanner
    @ObservationIgnored private let fileStore: LayoutFileStore
    @ObservationIgnored private let writer: LayoutWriter
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var isScanPending = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private let logger = LogArea.layout.logger

    init(scanner: CatalogScanner, fileStore: LayoutFileStore, preferences: Preferences) {
        self.scanner = scanner
        self.fileStore = fileStore
        self.preferences = preferences
        writer = LayoutWriter(fileStore: fileStore)
    }

    /// The installed app for a placed ID, or nil while the catalog does not know it.
    func app(for id: AppID) -> InstalledApp? {
        catalog[id]
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
