import Foundation

/// Looks up a short description and header image for a game the user already has installed, from
/// Steam's public storefront API - no login, no API key, just the numeric appID (which is not
/// sensitive - it's the same ID visible in the game's own store URL). Purely cosmetic: every card
/// already works without this, so any failure here (offline, API hiccup) is silently ignored.
///
/// Everything is cached to disk after the first successful fetch, so this only ever hits the network
/// once per game, ever - opening Game Mode again, or relaunching ExeDock, reads straight from disk.
actor SteamStoreInfoCache {
    static let shared = SteamStoreInfoCache()

    private var memoryCache: [String: SteamStoreInfo?] = [:]
    private let cacheDir = ("~/Library/Application Support/ExeDock/StoreInfoCache" as NSString).expandingTildeInPath

    func info(for appID: String) async -> SteamStoreInfo? {
        if let cached = memoryCache[appID] {
            return cached
        }
        if let onDisk = readFromDisk(appID) {
            memoryCache[appID] = onDisk
            return onDisk
        }
        let fetched = await fetchFromNetwork(appID)
        memoryCache[appID] = fetched
        if let fetched {
            writeToDisk(appID, fetched)
        }
        return fetched
    }

    private func fetchFromNetwork(_ appID: String) async -> SteamStoreInfo? {
        guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&l=english") else {
            DiagnosticsLog.log("Store info [\(appID)]: couldn't build appdetails URL")
            return nil
        }
        let responseResult: (data: Data, response: URLResponse)
        do {
            responseResult = try await URLSession.shared.data(from: url)
        } catch {
            DiagnosticsLog.log("Store info [\(appID)]: request failed - \(error.localizedDescription)")
            return nil
        }
        guard let http = responseResult.response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (responseResult.response as? HTTPURLResponse)?.statusCode
            DiagnosticsLog.log("Store info [\(appID)]: bad HTTP status \(status.map(String.init) ?? "?")")
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: responseResult.data) as? [String: Any],
              let entry = json[appID] as? [String: Any],
              entry["success"] as? Bool == true,
              let appData = entry["data"] as? [String: Any] else {
            DiagnosticsLog.log("Store info [\(appID)]: response didn't parse as expected (app may be delisted, or Steam changed the response shape)")
            return nil
        }

        let description = (appData["short_description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var headerImagePath: String?
        if let headerImageURLString = appData["header_image"] as? String, let headerImageURL = URL(string: headerImageURLString) {
            headerImagePath = await downloadHeaderImage(headerImageURL, appID: appID)
        }

        guard description?.isEmpty == false || headerImagePath != nil else {
            DiagnosticsLog.log("Store info [\(appID)]: fetched OK but had neither a description nor header art")
            return nil
        }
        DiagnosticsLog.log("Store info [\(appID)]: OK (description: \(description?.isEmpty == false), headerImage: \(headerImagePath != nil))")
        return SteamStoreInfo(shortDescription: (description?.isEmpty == false) ? description : nil, headerImagePath: headerImagePath)
    }

    private func downloadHeaderImage(_ url: URL, appID: String) async -> String? {
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let destination = (cacheDir as NSString).appendingPathComponent("\(appID)-header.jpg")
        let downloadResult: (url: URL, response: URLResponse)
        do {
            downloadResult = try await URLSession.shared.download(from: url)
        } catch {
            DiagnosticsLog.log("Store info [\(appID)]: header art download failed - \(error.localizedDescription)")
            return nil
        }
        guard let http = downloadResult.response as? HTTPURLResponse, http.statusCode == 200 else {
            DiagnosticsLog.log("Store info [\(appID)]: header art request returned a bad HTTP status")
            return nil
        }
        try? FileManager.default.removeItem(atPath: destination)
        guard (try? FileManager.default.moveItem(at: downloadResult.url, to: URL(fileURLWithPath: destination))) != nil else {
            DiagnosticsLog.log("Store info [\(appID)]: couldn't move downloaded header art into place")
            return nil
        }
        return destination
    }

    private func metadataPath(for appID: String) -> String {
        (cacheDir as NSString).appendingPathComponent("\(appID).json")
    }

    private func readFromDisk(_ appID: String) -> SteamStoreInfo? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath(for: appID))) else { return nil }
        return try? JSONDecoder().decode(SteamStoreInfo.self, from: data)
    }

    private func writeToDisk(_ appID: String, _ info: SteamStoreInfo) {
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(info) else { return }
        try? data.write(to: URL(fileURLWithPath: metadataPath(for: appID)))
    }
}
