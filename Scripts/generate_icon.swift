#!/usr/bin/env swift
// Regenerates Sources/ExeDock/Resources/AppIcon.iconset/*.png with a game-controller glyph on a
// gaming-purple gradient background, replacing whatever placeholder/previous artwork is there.
// Run with: swift Scripts/generate_icon.swift
import AppKit

let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let scriptDir = (#filePath as NSString).deletingLastPathComponent
let outputDir = (scriptDir as NSString).appendingPathComponent("../Sources/ExeDock/Resources/AppIcon.iconset")
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func renderIcon(pixelSize: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(pixelSize), pixelsHigh: Int(pixelSize),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let rect = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    // macOS "squircle" app icon corner radius is roughly 22.5% of the edge, matching system icons.
    let cornerRadius = pixelSize * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    ctx.saveGState()
    path.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.53, green: 0.33, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.52, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -90)
    ctx.restoreGState()

    // Centered white gamecontroller glyph, clipped from the SF Symbol's own alpha mask so it tints
    // cleanly regardless of the symbol's native rendering mode.
    let symbolPointSize = pixelSize * 0.52
    guard let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: symbolPointSize, weight: .medium)) else {
        fatalError("gamecontroller.fill symbol unavailable")
    }
    var proposedRect = CGRect(origin: .zero, size: symbol.size)
    guard let cgSymbol = symbol.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
        fatalError("couldn't rasterize symbol")
    }
    let symbolSize = CGSize(width: CGFloat(cgSymbol.width), height: CGFloat(cgSymbol.height))
    let scale = min((pixelSize * 0.6) / symbolSize.width, (pixelSize * 0.6) / symbolSize.height)
    let drawSize = CGSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
    let drawRect = CGRect(
        x: (pixelSize - drawSize.width) / 2,
        y: (pixelSize - drawSize.height) / 2,
        width: drawSize.width, height: drawSize.height
    )

    ctx.saveGState()
    ctx.clip(to: drawRect, mask: cgSymbol)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(drawRect)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, px) in sizes {
    let rep = renderIcon(pixelSize: px)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode \(name)")
    }
    let path = (outputDir as NSString).appendingPathComponent(name)
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(Int(px))px)")
}
