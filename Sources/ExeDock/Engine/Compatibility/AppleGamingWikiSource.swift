import Foundation

/// Fetches a game's AppleGamingWiki page via its public, unauthenticated MediaWiki API (confirmed
/// live during design: a plain `URLSession` GET works fine, no special headers needed) and hands
/// the raw wikitext to `AppleGamingWikiParser`. Tries the game's name as a direct page title first
/// (most AppleGamingWiki pages are literally `Game_Name` with underscores); if that page doesn't
/// exist, falls back to the wiki's own search so a close-but-not-exact title still resolves.
struct AppleGamingWikiSource: CompatibilitySource {
    let name = "AppleGamingWiki"
    private static let base = "https://www.applegamingwiki.com/w/api.php"

    func fetchReports(for game: SteamGame) async -> [CompatibilityReport] {
        let guessedTitle = Self.slugify(game.name)
        if let report = await fetchPage(title: guessedTitle) {
            return [report]
        }
        guard let foundTitle = await searchForTitle(game.name), foundTitle != guessedTitle else { return [] }
        if let report = await fetchPage(title: foundTitle) {
            return [report]
        }
        return []
    }

    private func fetchPage(title: String) async -> CompatibilityReport? {
        var components = URLComponents(string: Self.base)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "page", value: title),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "prop", value: "wikitext"),
        ]
        guard let url = components.url else { return nil }

        let result: (data: Data, response: URLResponse)
        do {
            result = try await URLSession.shared.data(from: url)
        } catch {
            DiagnosticsLog.log("AppleGamingWiki [\(title)]: request failed - \(error.localizedDescription)")
            return nil
        }
        guard (result.response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: result.data) as? [String: Any] else {
            DiagnosticsLog.log("AppleGamingWiki [\(title)]: bad response")
            return nil
        }
        if json["error"] != nil {
            return nil // page just doesn't exist under this title - not an error worth logging
        }
        guard let parse = json["parse"] as? [String: Any],
              let wikitextField = parse["wikitext"] as? [String: Any],
              let wikitext = wikitextField["*"] as? String else {
            DiagnosticsLog.log("AppleGamingWiki [\(title)]: response didn't parse as expected")
            return nil
        }

        let pageURL = "https://www.applegamingwiki.com/wiki/\(title)"
        let report = AppleGamingWikiParser.parse(wikitext: wikitext, pageURL: pageURL)
        DiagnosticsLog.log("AppleGamingWiki [\(title)]: \(report != nil ? "found usable evidence" : "page exists but had nothing usable")")
        return report
    }

    private func searchForTitle(_ query: String) async -> String? {
        var components = URLComponents(string: Self.base)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1, let titles = json[1] as? [String], let firstTitle = titles.first else {
            return nil
        }
        return Self.slugify(firstTitle)
    }

    static func slugify(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "_")
    }
}
