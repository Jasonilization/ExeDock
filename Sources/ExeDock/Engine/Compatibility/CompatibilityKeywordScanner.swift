import Foundation

/// Pure, deterministic keyword detection shared by every compatibility source - each source only
/// needs to hand it plain text (wikitext, an issue body, whatever) and get back which settings it
/// mentions, with polarity (recommended vs. reported-broken) and a text excerpt for evidence.
/// No networking, no LLM - just `NSRegularExpression` keyword matching plus a conservative nearby-
/// negation check, so this is unit-testable with fixture strings alone.
enum CompatibilityKeywordScanner {
    struct Mention {
        let polarity: Bool
        let snippet: String
    }

    enum Keyword: CaseIterable {
        case d3dMetal, dxvk, dxmt, vkd3d, esync, msync, fsync

        var patterns: [String] {
            switch self {
            case .d3dMetal: return ["D3DMetal", "D3D Metal"]
            case .dxvk: return ["DXVK"]
            case .dxmt: return ["DXMT"]
            case .vkd3d: return ["VKD3D"]
            case .esync: return ["ESync"]
            case .msync: return ["MSync"]
            case .fsync: return ["FSync"]
            }
        }

        func apply(_ polarity: Bool, to settings: inout DetectedSettings) {
            switch self {
            case .d3dMetal: settings.d3dMetal = polarity
            case .dxvk: settings.dxvk = polarity
            case .dxmt: settings.dxmt = polarity
            case .vkd3d: settings.mentionsVKD3D = true
            case .esync: settings.wineESync = polarity
            case .msync: settings.wineMSync = polarity
            case .fsync: settings.mentionsFsync = true
            }
        }
    }

    /// Scans `text` for every known keyword and returns the combined settings + excerpts (capped
    /// at 3, so one source's evidence stays skimmable rather than dumping the whole page).
    static func scan(_ text: String) -> (settings: DetectedSettings, excerpts: [String]) {
        var settings = DetectedSettings()
        var excerpts: [String] = []
        for keyword in Keyword.allCases {
            guard let mention = firstMention(of: keyword, in: text) else { continue }
            keyword.apply(mention.polarity, to: &settings)
            excerpts.append(mention.snippet)
        }
        return (settings, Array(excerpts.prefix(3)))
    }

    static func firstMention(of keyword: Keyword, in text: String) -> Mention? {
        for pattern in keyword.patterns {
            guard let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: pattern), options: .caseInsensitive) else {
                continue
            }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range), let matchRange = Range(match.range, in: text) else { continue }

            let contextStart = text.index(matchRange.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
            let contextEnd = text.index(matchRange.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
            let snippet = String(text[contextStart..<contextEnd])
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)

            return Mention(polarity: !hasNegationInSentence(around: matchRange, in: text), snippet: snippet)
        }
        return nil
    }

    /// Deliberately conservative, not a real negation detector - a missed negation just makes one
    /// report read slightly more positive than it should; `CompatibilityAggregator`'s multi-source
    /// agreement requirement is the real safety net against any single mis-read mention swinging a
    /// recommendation. Scoped to the keyword's own sentence (bounded by `.`/`!`/`?` on each side) so
    /// a negation word describing a *different* keyword in an adjacent sentence doesn't bleed in -
    /// and checked on both sides of the keyword, since "X is broken" (negation after) is just as
    /// common as "avoid X" (negation before).
    private static func hasNegationInSentence(around matchRange: Range<String.Index>, in text: String) -> Bool {
        let boundary = CharacterSet(charactersIn: ".!?")

        let windowStart = text.index(matchRange.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
        let before = text[windowStart..<matchRange.lowerBound]
        let sentenceStart = before.rangeOfCharacter(from: boundary, options: .backwards)?.upperBound ?? windowStart

        let windowEnd = text.index(matchRange.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
        let after = text[matchRange.upperBound..<windowEnd]
        let sentenceEnd = after.rangeOfCharacter(from: boundary)?.lowerBound ?? windowEnd

        let sentence = text[sentenceStart..<sentenceEnd].lowercased()
        let negationWords = ["not ", "n't ", "avoid", "broken", "disable", "without", "unplayable", "worse than"]
        return negationWords.contains { sentence.contains($0) }
    }
}
