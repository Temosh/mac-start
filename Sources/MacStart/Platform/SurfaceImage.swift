import CoreGraphics
import CoreVideo
import VideoToolbox

/// Bitmaps that live in an IOSurface, which Core Animation shows as they are. From ordinary memory, Core Animation
/// keeps its own copy of every image it shows, for as long as the image lives.
enum SurfaceImage {
    /// An sRGB image of `width` × `height` pixels, cleared, then drawn by `draw` in a context whose origin is the
    /// bottom-left corner. Nil when the surface cannot be made. Safe off the main thread.
    nonisolated static func make(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let buffer = makeBuffer(width: width, height: height, colorSpace: colorSpace),
            fill(buffer, width: width, height: height, colorSpace: colorSpace, draw: draw)
        else {
            return nil
        }
        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image) == noErr else {
            return nil
        }
        return image
    }

    /// A pixel buffer backed by an IOSurface, in the BGRA layout Core Animation shows directly.
    private nonisolated static func makeBuffer(width: Int, height: Int, colorSpace: CGColorSpace) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any]() as CFDictionary,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var buffer: CVPixelBuffer?
        guard
            CVPixelBufferCreate(
                nil, max(width, 1), max(height, 1), kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
                == kCVReturnSuccess,
            let buffer
        else {
            return nil
        }
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        return buffer
    }

    /// Clears the buffer and lets `draw` draw into it. Returns false when the buffer cannot be drawn into.
    private nonisolated static func fill(
        _ buffer: CVPixelBuffer,
        width: Int,
        height: Int,
        colorSpace: CGColorSpace,
        draw: (CGContext) -> Void
    ) -> Bool {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: max(width, 1),
                height: max(height, 1),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            return false
        }
        context.clear(CGRect(x: 0, y: 0, width: max(width, 1), height: max(height, 1)))
        draw(context)
        return true
    }
}
