import Foundation

/// Turns "here's an exe/folder someone picked" into real library metadata - local PE version info
/// first (always available, no network), then an attempt to match it against Steam's own public
/// catalog for real description/artwork, but only when confident. Nothing here ever blocks adding a
/// game: if nothing matches, the game is still added using only what the exe itself says about
/// itself (or, failing that, its own filename) - exactly per spec.
enum CustomGameMetadataDiscovery {
    /// Runs the full pipeline for a freshly-picked exe (and, if it came from a folder pick rather
    /// than a lone file, that folder's own name as a second identification candidate).
    static func discover(exePath: String, folderName: String?) async -> DiscoveredMetadata {
        var metadata = DiscoveredMetadata()

        let peInfo = PEVersionInfoReader.read(exePath: exePath)
        metadata.productName = peInfo?.productName
        metadata.fileDescription = peInfo?.fileDescription
        metadata.publisher = peInfo?.companyName
        metadata.fileVersion = peInfo?.fileVersion

        guard let candidate = identificationCandidate(peProductName: peInfo?.productName, folderName: folderName, exePath: exePath),
              let appID = await confidentSteamMatch(for: candidate) else {
            return metadata
        }
        if let storeInfo = await SteamStoreInfoCache.shared.info(for: appID) {
            metadata.steamDescription = storeInfo.shortDescription
            metadata.steamArtworkPath = storeInfo.headerImagePath
        }
        return metadata
    }

    /// PE ProductName > folder name (if the user picked a folder) > a cleaned-up exe filename - the
    /// same order used both for identification here and, when nothing better was ever discovered,
    /// for `CustomGame.effectiveName`'s own fallback chain.
    static func identificationCandidate(peProductName: String?, folderName: String?, exePath: String) -> String? {
        if let peProductName, !peProductName.isEmpty { return peProductName }
        if let folderName, !folderName.isEmpty { return folderName }
        let cleaned = CustomGame.cleanedName(fromExePath: exePath)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Steam's own public, unauthenticated search - the same kind of storefront call
    /// `SteamStoreInfoCache` already makes, just for search instead of a known appid. Only returns
    /// an appid when a result's own name matches `candidate` confidently - exact, case/punctuation-
    /// insensitive - never a fuzzy "closest" guess. A miss here just means the game gets added with
    /// local-only info, a completely fine, expected outcome for anything not sold on Steam.
    private static func confidentSteamMatch(for candidate: String) async -> String? {
        var components = URLComponents(string: "https://store.steampowered.com/api/storesearch/")
        components?.queryItems = [
            URLQueryItem(name: "term", value: candidate),
            URLQueryItem(name: "l", value: "english"),
            URLQueryItem(name: "cc", value: "US"),
        ]
        guard let url = components?.url else { return nil }

        let result: (data: Data, response: URLResponse)
        do {
            result = try await URLSession.shared.data(from: url)
        } catch {
            DiagnosticsLog.log("Custom game metadata: storesearch request failed - \(error.localizedDescription)")
            return nil
        }
        guard let http = result.response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: result.data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return nil
        }

        let normalizedCandidate = normalize(candidate)
        for item in items {
            guard item["type"] as? String == "app",
                  let name = item["name"] as? String,
                  let id = item["id"] as? Int else { continue }
            if normalize(name) == normalizedCandidate {
                DiagnosticsLog.log("Custom game metadata: confident Steam match for \"\(candidate)\" -> appid \(id)")
                return String(id)
            }
        }
        return nil
    }

    /// Case/punctuation-insensitive comparison key - "UNDERTALE" and "Undertale" (or "Hollow-Knight"
    /// and "Hollow Knight") should count as the same name; anything less strict risks a wrong match.
    private static func normalize(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
