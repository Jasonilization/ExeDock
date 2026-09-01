import CoreText
import Foundation

/// Registers the real, bundled display typefaces each `PlaydockSkin` uses for its most prominent
/// text (game/section titles) - "the 10 UI skins should look exactly like the preview websites,"
/// per live feedback, which used real Google Fonts (OFL-licensed, freely embeddable - not a
/// custom typeface someone would need a license for) for each skin's headline face. `Font.Design`
/// alone (`.rounded`/`.serif`/`.monospaced`) gets a skin *most* of the way there for body text with
/// zero bundling risk, but a real display face is what actually makes a headline read as "this is
/// Neobrutalist" rather than "this is the same system font, bolder."
enum SkinFonts {
    /// (bundled file name without extension) -> the exact PostScript name SwiftUI's
    /// `Font.custom(_:size:)` needs - confirmed via CoreText against the real downloaded files
    /// (`CTFontCopyName(_, kCTFontPostScriptNameKey)`), not guessed from the file name.
    private static let files: [(file: String, postscriptName: String)] = [
        ("archivo-black", "ArchivoBlack-Regular"),
        ("barlowcondensed", "BarlowCondensed-Bold"),
        ("fraunces", "Fraunces-9ptBlack"),
        ("jetbrainsmono", "JetBrainsMono-Regular"),
        ("orbitron", "Orbitron-Regular"),
        ("pressstart2p", "PressStart2P-Regular"),
        ("quicksand", "Quicksand-Light"),
        ("righteous", "Righteous-Regular"),
    ]

    private static var didRegister = false

    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let fontsDir = resourceURL.appendingPathComponent("Fonts")
        for (file, _) in files {
            let url = fontsDir.appendingPathComponent("\(file).ttf")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let message = error?.takeRetainedValue().localizedDescription ?? "unknown error"
                DiagnosticsLog.log("SkinFonts: couldn't register \(file).ttf - \(message)")
            }
        }
    }

    /// The registered PostScript name for a skin's own display face - `nil` for a skin that
    /// deliberately stays on the system font (Quiet Luxury's whole point is looking native; Minimal
    /// and Soft UI lean on `Font.Design` alone rather than a loud display face).
    static func postscriptName(for skin: PlaydockSkin) -> String? {
        switch skin {
        case .luxury, .minimal: return nil
        case .glass: return nil // Sora wasn't worth a second download for one weight - .rounded carries it
        case .brutalist: return "ArchivoBlack-Regular"
        case .cyber: return "Orbitron-Regular"
        case .soft: return "Quicksand-Light"
        case .editorial: return "Fraunces-9ptBlack"
        case .pixel: return "PressStart2P-Regular"
        case .console: return "BarlowCondensed-Bold"
        case .vapor: return "Righteous-Regular"
        }
    }
}
