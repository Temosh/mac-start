import AppKit
import MacStartCore

/// App icons from `NSWorkspace`, cached in memory.
@MainActor
final class IconProvider {
    private var cache: [CacheKey: NSImage] = [:]

    /// The app's icon. The cache key includes the version, so an updated app gets its new icon.
    func icon(for app: InstalledApp) -> NSImage {
        let key = CacheKey(path: app.id.path, version: app.version)
        if let cached = cache[key] {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: app.bundleURL.path(percentEncoded: false))
        cache[key] = icon
        return icon
    }

    private struct CacheKey: Hashable {
        let path: String
        let version: String?
    }
}
