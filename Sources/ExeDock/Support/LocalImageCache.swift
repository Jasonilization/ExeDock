import AppKit

/// Caches decoded images for local files (the Steam avatar, cached game header art) so a SwiftUI
/// view re-rendering for an unrelated reason - e.g. `statusMessage` changing while the dashboard is
/// visible - doesn't re-read and re-decode the same file from disk every time. `AppIconProvider`
/// does the same thing for Finder icons; this covers literal image files.
enum LocalImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(atPath path: String) -> NSImage? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
