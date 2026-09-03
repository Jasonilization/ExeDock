import AppKit
import CoreImage
import SwiftUI

/// A game's own dominant color, sampled from its real cached artwork - so a card's accent can pick
/// up a subtle hint of that specific game's palette instead of every card under a skin using the
/// exact same static swatch. Blended with (never replacing) the active skin's own accent by
/// `PlaydockSkin.blended(withGameColor:)`, so a skin's real identity stays intact and this only
/// ever reads as a per-game variation on it.
enum GameArtColor {
    private static let cache: NSCache<NSString, NSColor> = {
        let cache = NSCache<NSString, NSColor>()
        cache.countLimit = 400 // one entry per distinct art path ever sampled this session
        return cache
    }()

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// The average color of the image already cached at `path` (via `LocalImageCache`, so this
    /// never decodes a file a second time) - `nil` if there's no image there or the sample
    /// genuinely can't be computed. Cheap enough to call from a view's own body: a real average-
    /// color extraction (`CIAreaAverage`, the same standard technique system UI itself uses for
    /// this) over an already-downsampled image, and the result is cached by path afterward.
    static func dominantColor(forImagePath path: String) -> Color? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return Color(nsColor: cached)
        }
        guard let nsImage = LocalImageCache.image(atPath: path),
              let tiff = nsImage.tiffRepresentation,
              let ciImage = CIImage(data: tiff) else { return nil }

        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0,
              let averageFilter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: extent),
              ]),
              let outputImage = averageFilter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let color = NSColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        cache.setObject(color, forKey: key)
        return Color(nsColor: color)
    }
}

extension Color {
    /// A linear RGB blend toward `other` - `amount` 0 keeps `self` unchanged, 1 becomes `other`
    /// entirely. Used to fold a game's own sampled color into a skin's fixed accent at a modest
    /// weight, never enough to override the skin's own identity.
    func blended(toward other: Color, amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let b = NSColor(other).usingColorSpace(.deviceRGB) ?? NSColor(other)
        let t = min(max(amount, 0), 1)
        return Color(
            red: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t
        )
    }
}
