import AppKit
import MacStartCore

/// App icons from `NSWorkspace`, drawn at the size they show at and cached in memory. A pre-sized bitmap keeps
/// paging and dragging smooth, because the grid never scales a large icon while it moves. `prewarm(_:)` draws
/// icons in the background ahead of time, so opening the overlay does not draw them either.
@MainActor
final class IconProvider {
    private var cache: [IconKey: NSImage] = [:]

    private var scale: CGFloat {
        NSScreen.screens.first?.backingScaleFactor ?? 2
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

    /// Draws the app's icon into a square bitmap of the job's pixel size. Safe off the main thread: each call
    /// gets its own image from `NSWorkspace` and draws it into its own context.
    private nonisolated static func render(_ job: IconJob) -> CGImage? {
        let source = NSWorkspace.shared.icon(forFile: job.path)
        var proposedRect = CGRect(x: 0, y: 0, width: job.pixels, height: job.pixels)
        guard
            let image = source.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: job.pixels,
                height: job.pixels,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: job.pixels, height: job.pixels))
        return context.makeImage()
    }
}

/// One cached icon: an app at a pixel size. The version makes an updated app draw its new icon.
private struct IconKey: Hashable, Sendable {
    let path: String
    let version: String?
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
        pixels = max(Int((side * scale).rounded()), 1)
        key = IconKey(path: app.id.path, version: app.version, pixels: pixels)
        path = app.bundleURL.path(percentEncoded: false)
        self.side = side
    }
}
