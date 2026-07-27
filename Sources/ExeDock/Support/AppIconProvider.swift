import AppKit

/// Resolves a real, recognizable icon for a detected app or file instead of a generic placeholder
/// symbol - the wrapper app's own Finder icon for anything Sikarugir already built (e.g. Steam's or
/// Pragmata's real icon), or the file's own Finder icon otherwise.
enum AppIconProvider {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for app: DetectedApp) -> NSImage {
        if case .sikarugirWrapper(let appPath) = app.bottle.kind {
            return icon(forPath: appPath)
        }
        return icon(forPath: app.exePath)
    }

    static func icon(forPath path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: key)
        return image
    }
}
