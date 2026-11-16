// Draws the placeholder app icon, a 3 x 3 grid of colored tiles on a dark rounded square,
// into an .iconset folder for `iconutil`. Replace the PNGs when real artwork exists.
//
// Usage: swift scripts/make-placeholder-icon.swift Support/AppIcon.iconset

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One PNG of the iconset: its file name and its edge length in pixels.
struct IconImage {
    let fileName: String
    let pixels: Int
    let isRetina: Bool
}

let iconImages: [IconImage] = [16, 32, 128, 256, 512].flatMap { points in
    [
        IconImage(fileName: "icon_\(points)x\(points).png", pixels: points, isRetina: false),
        IconImage(fileName: "icon_\(points)x\(points)@2x.png", pixels: points * 2, isRetina: true),
    ]
}

/// Tile colors in reading order, top-left first.
let tileColors: [(red: CGFloat, green: CGFloat, blue: CGFloat)] = [
    (1.00, 0.27, 0.23), (1.00, 0.62, 0.04), (1.00, 0.84, 0.04),
    (0.20, 0.78, 0.35), (0.19, 0.69, 0.78), (0.04, 0.52, 1.00),
    (0.37, 0.36, 0.90), (0.75, 0.35, 0.95), (1.00, 0.22, 0.37),
]

func drawIcon(pixels: Int) -> CGImage {
    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        fatalError("Cannot create a \(pixels) px bitmap context")
    }

    // Geometry on the 1024 pt macOS icon grid, scaled to the target size.
    let scale = CGFloat(pixels) / 1024
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(
        roundedRect: body.applying(CGAffineTransform(scaleX: scale, y: scale)),
        cornerWidth: 185 * scale,
        cornerHeight: 185 * scale,
        transform: nil
    )

    // Body with a soft drop shadow.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10 * scale),
        blur: 20 * scale,
        color: CGColor(gray: 0, alpha: 0.35)
    )
    context.addPath(bodyPath)
    context.setFillColor(CGColor(red: 0.11, green: 0.11, blue: 0.18, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Vertical gradient inside the body, lighter at the top.
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let gradientColors = [
        CGColor(red: 0.20, green: 0.22, blue: 0.36, alpha: 1),
        CGColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 1),
    ]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors as CFArray, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: body.maxY * scale),
            end: CGPoint(x: 0, y: body.minY * scale),
            options: []
        )
    }
    context.restoreGState()

    // 3 x 3 tiles, centered in the body.
    let margin: CGFloat = 150
    let gap: CGFloat = 56
    let tile = (body.width - 2 * margin - 2 * gap) / 3
    for (index, color) in tileColors.enumerated() {
        let column = CGFloat(index % 3)
        let row = CGFloat(index / 3)
        let tileRect = CGRect(
            x: body.minX + margin + column * (tile + gap),
            y: body.maxY - margin - tile - row * (tile + gap),
            width: tile,
            height: tile
        ).applying(CGAffineTransform(scaleX: scale, y: scale))
        context.addPath(
            CGPath(
                roundedRect: tileRect,
                cornerWidth: tile * 0.28 * scale,
                cornerHeight: tile * 0.28 * scale,
                transform: nil
            )
        )
        context.setFillColor(CGColor(red: color.red, green: color.green, blue: color.blue, alpha: 1))
        context.fillPath()
    }

    guard let image = context.makeImage() else {
        fatalError("Cannot render the \(pixels) px icon")
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL, isRetina: Bool) {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        fatalError("Cannot create \(url.path)")
    }
    let dpi = isRetina ? 144 : 72
    let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Cannot write \(url.path)")
    }
}

guard CommandLine.arguments.count == 2 else {
    print("Usage: swift scripts/make-placeholder-icon.swift <output .iconset folder>")
    exit(64)
}
let outputFolder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
for iconImage in iconImages {
    writePNG(
        drawIcon(pixels: iconImage.pixels),
        to: outputFolder.appendingPathComponent(iconImage.fileName),
        isRetina: iconImage.isRetina
    )
}
print("Wrote \(iconImages.count) images to \(outputFolder.path)")
