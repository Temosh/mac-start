import CoreServices
import Foundation
import MacStartCore
import os

/// Watches the app folders with FSEvents and reports changes after they settle.
///
/// FSEvents groups the changes that arrive within `latency` seconds into one callback, which is the debounce:
/// installing an app reports once, not once per copied file. Changes that cannot change the catalog, such as an app
/// writing inside its own bundle, report nothing; see `CatalogChangeFilter`.
@MainActor
final class CatalogWatcher {
    private let onChange: @MainActor () -> Void
    private let filter: CatalogChangeFilter
    private var stream: FSEventStreamRef?
    private let logger = LogArea.catalog.logger

    /// Starts watching `roots`. `onChange` runs on the main actor.
    init(roots: [URL], latency: TimeInterval = 2, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        filter = CatalogChangeFilter(roots: roots)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = roots.map { $0.path(percentEncoded: false) } as CFArray
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else {
                return
            }
            let watcher = Unmanaged<CatalogWatcher>.fromOpaque(info).takeUnretainedValue()
            // The stream uses CF types, so the paths come as an array of strings.
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            let flags = (0..<count).map { eventFlags[$0] }
            // The stream is scheduled on the main queue.
            MainActor.assumeIsolated { watcher.handle(paths: paths, flags: flags) }
        }
        guard
            let stream = FSEventStreamCreate(
                nil,
                callback,
                &context,
                paths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
            )
        else {
            logger.error("Cannot create the FSEvents stream for the app folders")
            return
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            logger.error("Cannot start the FSEvents stream for the app folders")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
    }

    isolated deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// Reports a change when any of the events can change the catalog. Events that FSEvents dropped could have
    /// been anything, so they count too.
    private func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        // Paths that cannot be read could have been anything as well.
        guard paths.count == flags.count else {
            onChange()
            return
        }
        let lostEvents = FSEventStreamEventFlags(
            kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagRootChanged
        )
        let canChangeCatalog = zip(paths, flags).contains { path, flag in
            flag & lostEvents != 0 || filter.canChangeCatalog(path: path)
        }
        guard canChangeCatalog else {
            logger.debug("Ignoring \(paths.count) changes inside app bundles or below the scan depth")
            return
        }
        onChange()
    }
}
