import AppKit
import CoreVideo
import MacStartCore
import VideoToolbox

/// App icons from `NSWorkspace`, drawn at the size they show at and cached in memory. A pre-sized bitmap keeps
/// paging and dragging smooth, because the grid never scales a large icon while it moves. `prewarm(_:)` draws
/// icons in the background ahead of time, so opening the overlay does not draw them either.
///
/// Each bitmap lives in an IOSurface, which Core Animation shows as it is. From ordinary memory, Core Animation
/// keeps its own copy of every image it shows, as long as the image lives: about 21 MB more for a 95-icon grid.
@MainActor
final class IconProvider {
    private var cache: [IconKey: NSImage] = [:]
    /// The grid icon's pixel size at the last prune. When it changes, every cached icon is of a size no longer shown.
    private var prunedGridPixels: Int?

    /// The gray prohibition sign that macOS puts on apps that cannot run on this Mac. A dragged icon shows it where
    /// it cannot drop. Nil when this macOS has no such icon.
    private(set) lazy var prohibitionMark: NSImage? = Self.loadProhibitionMark()

    private var scale: CGFloat {
        NSScreen.screens.first?.backingScaleFactor ?? 2
    }

    private static func loadProhibitionMark() -> NSImage? {
        let path = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Unsupported.icns"
        guard let image = NSImage(contentsOfFile: path) else {
            LogArea.overlay.logger.error("No system prohibition mark at \(path)")
            return nil
        }
        return image
    }

    /// The app's icon as a square bitmap of `side` points. The cache key includes the version, so an updated app
    /// gets its new icon. An icon that was not prewarmed is drawn here, on the main actor.
    func icon(for app: InstalledApp, side: CGFloat) -> NSImage {
        let job = IconJob(app: app, side: side, scale: scale)
        if let cached = cache[job.key] {
            return cached
        }
        let icon =
            Self.render(job).map { NSImage(cgImage: $0, size: NSSize(width: side, height: side)) }
            ?? NSWorkspace.shared.icon(forFile: job.path)
        cache[job.key] = icon
        return icon
    }

    /// Draws the icons that are not cached yet off the main actor.
    func prewarm(_ requests: [(app: InstalledApp, side: CGFloat)]) async {
        let scale = scale
        var queued = Set<IconKey>()
        let jobs =
            requests
            .map { IconJob(app: $0.app, side: $0.side, scale: scale) }
            .filter { cache[$0.key] == nil && queued.insert($0.key).inserted }
        guard !jobs.isEmpty else {
            return
        }
        for (job, image) in await Self.render(jobs) where cache[job.key] == nil {
            cache[job.key] = NSImage(cgImage: image, size: NSSize(width: job.side, height: job.side))
        }
    }

    @concurrent
    private nonisolated static func render(_ jobs: [IconJob]) async -> [(IconJob, CGImage)] {
        jobs.compactMap { job in render(job).map { (job, $0) } }
    }

    /// Forgets the icons nothing shows any more: those of apps that left the catalog or changed version, and all of
    /// them once the grid's icon size or the display scale changes. Without it, the cache would keep every bitmap it
    /// ever drew, about 0.2 MB each, for the life of the app.
    func prune(keepingAppsIn catalog: Catalog, gridIconSide: CGFloat) {
        let gridPixels = IconJob.pixels(side: gridIconSide, scale: scale)
        defer { prunedGridPixels = gridPixels }
        if let prunedGridPixels, prunedGridPixels != gridPixels {
            cache.removeAll()
            return
        }
        let installed = Set(catalog.apps.map { IconKey.App(path: $0.id.path, version: $0.version) })
        cache = cache.filter { installed.contains($0.key.app) }
    }

    /// Draws the app's icon into a square bitmap of the job's pixel size. Safe off the main thread: each call
    /// gets its own image from `NSWorkspace` and draws it into its own pixel buffer.
    private nonisolated static func render(_ job: IconJob) -> CGImage? {
        let source = NSWorkspace.shared.icon(forFile: job.path)
        var proposedRect = CGRect(x: 0, y: 0, width: job.pixels, height: job.pixels)
        guard
            let image = source.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let buffer = makeSurfaceBuffer(side: job.pixels, colorSpace: colorSpace),
            draw(image, into: buffer, side: job.pixels, colorSpace: colorSpace)
        else {
            return nil
        }
        var surfaceImage: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &surfaceImage) == noErr else {
            return nil
        }
        return surfaceImage
    }

    /// A square pixel buffer backed by an IOSurface, in the BGRA layout Core Animation shows directly.
    private nonisolated static func makeSurfaceBuffer(side: Int, colorSpace: CGColorSpace) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any]() as CFDictionary,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var buffer: CVPixelBuffer?
        guard
            CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
                == kCVReturnSuccess,
            let buffer
        else {
            return nil
        }
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        return buffer
    }

    /// Draws `image` to fill the buffer. Returns false when the buffer cannot be drawn into.
    private nonisolated static func draw(
        _ image: CGImage,
        into buffer: CVPixelBuffer,
        side: Int,
        colorSpace: CGColorSpace
    ) -> Bool {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            return false
        }
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        context.clear(bounds)
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
        return true
    }
}

/// One cached icon: an app at a pixel size. The version makes an updated app draw its new icon.
private struct IconKey: Hashable, Sendable {
    /// An installed app as the cache tells it apart.
    struct App: Hashable, Sendable {
        let path: String
        let version: String?
    }

    let app: App
    let pixels: Int
}

/// An icon to draw.
private struct IconJob: Sendable {
    let key: IconKey
    /// The bundle to take the icon from: the target of a linked app.
    let path: String
    let side: CGFloat
    let pixels: Int

    init(app: InstalledApp, side: CGFloat, scale: CGFloat) {
        pixels = Self.pixels(side: side, scale: scale)
        key = IconKey(app: IconKey.App(path: app.id.path, version: app.version), pixels: pixels)
        path = app.bundleURL.path(percentEncoded: false)
        self.side = side
    }

    /// The pixel size of a square icon of `side` points.
    static func pixels(side: CGFloat, scale: CGFloat) -> Int {
        max(Int((side * scale).rounded()), 1)
    }
}
