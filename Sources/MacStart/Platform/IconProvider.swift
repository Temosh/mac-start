import AppKit
import MacStartCore

/// App icons from `NSWorkspace`, drawn once at the size they show at and cached in memory. A pre-sized bitmap
/// keeps paging and dragging smooth, because the grid never scales a large icon while it moves.
@MainActor
final class IconProvider {
    private var cache: [CacheKey: NSImage] = [:]

    /// The app's icon as a square bitmap of `side` points for the main display's scale. The cache key includes
    /// the version, so an updated app gets its new icon.
    func icon(for app: InstalledApp, side: CGFloat) -> NSImage {
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        let pixels = max(Int((side * scale).rounded()), 1)
        let key = CacheKey(path: app.id.path, version: app.version, pixels: pixels)
        if let cached = cache[key] {
            return cached
        }
        let source = NSWorkspace.shared.icon(forFile: app.bundleURL.path(percentEncoded: false))
        let icon = Self.bitmap(of: source, side: side, pixels: pixels) ?? source
        cache[key] = icon
        return icon
    }

    private static func bitmap(of source: NSImage, side: CGFloat, pixels: Int) -> NSImage? {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixels,
                pixelsHigh: pixels,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else {
            return nil
        }
        // The size in points, set before drawing, so the context maps points to the bitmap's pixels.
        bitmap.size = NSSize(width: side, height: side)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: bitmap.size), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    private struct CacheKey: Hashable {
        let path: String
        let version: String?
        let pixels: Int
    }
}
