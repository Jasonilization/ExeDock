import Foundation

/// Searches GitHub's public issue/PR search for the game name plus known settings keywords.
/// Deliberately **not** scoped to a specific "Sikarugir" repo - there's no real, verified public
/// Sikarugir GitHub repo to search (the README's own reference to one was a dead placeholder link),
/// so fabricating a repo slug here would just silently return nothing. An unscoped search still
/// surfaces real, relevant results (verified live while designing this: searching "Red Dead
/// Redemption" + D3DMetal surfaced a real issue in `macgamingdb`, a crowd-sourced Mac gaming
/// compatibility repo). Unauthenticated GitHub search is rate-limited (~10 req/min) - this is
/// always called through `CompatibilityCache`, never in a loop.
struct GitHubCompatibilitySource: CompatibilitySource {
    let name = "GitHub"
    private static let searchURL = "https://api.github.com/search/issues"
    private static let keywordQuery = "D3DMetal OR DXVK OR DXMT OR VKD3D OR ESync OR MSync OR Wine"

    func fetchReports(id: String, name: String) async -> [CompatibilityReport] {
        var components = URLComponents(string: Self.searchURL)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "\"\(name)\" (\(Self.keywordQuery))"),
            URLQueryItem(name: "per_page", value: "5"),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let result: (data: Data, response: URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            DiagnosticsLog.log("GitHub compatibility search [\(name)]: request failed - \(error.localizedDescription)")
            return []
        }
        guard (result.response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: result.data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            DiagnosticsLog.log("GitHub compatibility search [\(name)]: bad response (possibly rate-limited)")
            return []
        }

        let reports = items.compactMap { item -> CompatibilityReport? in
            guard let title = item["title"] as? String, let url = item["html_url"] as? String else { return nil }
            let body = (item["body"] as? String) ?? ""
            let (settings, excerpts) = CompatibilityKeywordScanner.scan("\(title)\n\(body)")
            guard !settings.isEmpty else { return nil }
            let excerpt = excerpts.isEmpty ? title : excerpts.joined(separator: " […] ")
            return CompatibilityReport(sourceName: "GitHub", sourceURL: url, excerpt: excerpt, settings: settings)
        }
        DiagnosticsLog.log("GitHub compatibility search [\(name)]: \(reports.count) usable report(s) from \(items.count) result(s)")
        return reports
    }
}
