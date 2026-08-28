import Foundation

/// Pure, deterministic extraction from an AppleGamingWiki page's raw wikitext - no networking, so
/// this can be unit-tested with fixture strings. Real wikitext shape (confirmed live against
/// `Red_Dead_Redemption_2`/`Hollow_Knight` while designing this):
/// ```
/// {{Compatibility/macOS
/// |crossover       = perfect
/// |crossover notes = ...D3DMetal and ESync is turned on...MSync caused significant FPS drops...
/// |wine            = unplayable
/// }}
/// ```
enum AppleGamingWikiParser {
    static func parse(wikitext: String, pageURL: String) -> CompatibilityReport? {
        guard !wikitext.isEmpty else { return nil }

        let scanResult = CompatibilityKeywordScanner.scan(wikitext)
        var settings = scanResult.settings
        let excerpts = scanResult.excerpts

        let wineVerdict = fieldValue(named: "wine", in: wikitext)
        let crossoverVerdict = fieldValue(named: "crossover", in: wikitext)
        if wineVerdict == "unplayable" && crossoverVerdict == "unplayable" {
            settings.knownIssues.append("AppleGamingWiki reports this as unplayable via both Wine and CrossOver.")
        }

        guard !settings.isEmpty else { return nil }
        return CompatibilityReport(sourceName: "AppleGamingWiki", sourceURL: pageURL, excerpt: excerpts.joined(separator: " […] "), settings: settings)
    }

    /// A short, single-word-ish template field like `|wine = unplayable` - safe to regex directly
    /// since these values never span multiple lines, unlike the free-text `*_notes` fields the
    /// keyword scanner reads.
    private static func fieldValue(named fieldName: String, in text: String) -> String? {
        let pattern = "\\|\\s*\(NSRegularExpression.escapedPattern(for: fieldName))\\s*=\\s*([a-zA-Z0-9_-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange]).lowercased()
    }
}
