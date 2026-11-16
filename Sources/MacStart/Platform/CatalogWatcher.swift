import CoreServices
import Foundation
import MacStartCore
import os

/// Watches the app folders with FSEvents and reports changes after they settle.
///
/// FSEvents groups the changes that arrive within `latency` seconds into one callback, which is the debounce:
/// installing an app reports once, not once per copied file.
@MainActor
final class CatalogWatcher {
    private let onChange: @MainActor () -> Void
    private var stream: FSEventStreamRef?
    private let logger = LogArea.catalog.logger

    /// Starts watching `roots`. `onChange` runs on the main actor.
    init(roots: [URL], latency: TimeInterval = 2, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = roots.map { $0.path(percentEncoded: false) } as CFArray
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else {
                return
            }
            let watcher = Unmanaged<CatalogWatcher>.fromOpaque(info).takeUnretainedValue()
            // The stream is scheduled on the main queue.
            MainActor.assumeIsolated { watcher.onChange() }
        }
        guard
            let stream = FSEventStreamCreate(
                nil,
                callback,
                &context,
                paths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
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
}
