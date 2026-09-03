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

    /// The already-cached result for `path`, if any - safe to call from a view's own body since it
    /// never does any real work, just an `NSCache` lookup. `nil` until `dominantColor(forImagePath:)`
    /// has resolved at least once for this path.
    static func cachedColor(forImagePath path: String) -> Color? {
        cache.object(forKey: path as NSString).map { Color(nsColor: $0) }
    }

    /// The average color of the image already cached at `path` (via `LocalImageCache`, so this
    /// never decodes a file a second time) - `nil` if there's no image there or the sample
    /// genuinely can't be computed. Real work (`CIAreaAverage`, the same standard technique system
    /// UI itself uses for this, over an already-downsampled image) - measured live at ~230ms on its
    /// first real call (`CIContext`'s own one-time GPU pipeline setup) and under 2ms on every call
    /// after, so this must never run synchronously on the main thread the first time. Callers use
    /// this from a `.task(id:)`, matching every other per-entry art fetch already in this codebase
    /// (`LibraryPresentation.resolve`), and read `cachedColor(forImagePath:)` for the fast path.
    static func dominantColor(forImagePath path: String) async -> Color? {
        if let cached = cachedColor(forImagePath: path) { return cached }
        return await Task.detached(priority: .utility) {
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
            cache.setObject(color, forKey: path as NSString)
            return Color(nsColor: color)
        }.value
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
