import Foundation

struct RemoteEngineAsset: Equatable {
    /// Tarball name with no extension, e.g. "WS12WineSikarugir10.0_6" - matches the naming
    /// `SikarugirEngine` already uses for everything else.
    let name: String
    let downloadURL: URL
    let sizeBytes: Int
}

enum SikarugirEnginesRemoteError: Error, LocalizedError {
    case requestFailed
    case noAssetsFound

    var errorDescription: String? {
        switch self {
        case .requestFailed: return "Couldn't reach Sikarugir's engine releases on GitHub."
        case .noAssetsFound: return "No engine builds were found in Sikarugir's latest release."
        }
    }
}

/// Talks to the real, public `Sikarugir-App/Engines` GitHub repository - confirmed to be the exact
/// place Sikarugir Creator itself downloads engines from (the tarball names and byte sizes returned
/// here match exactly what Sikarugir Creator had already downloaded locally on this Mac). Lets
/// Playdock fetch an engine directly with no separate app required, and check whether a newer build
/// than whatever's cached locally has been published.
enum SikarugirEnginesRemote {
    private static let releasesURL = URL(string: "https://api.github.com/repos/Sikarugir-App/Engines/releases/latest")!

    static func fetchAvailableAssets() async throws -> [RemoteEngineAsset] {
        let result: (data: Data, response: URLResponse)
        do {
            result = try await URLSession.shared.data(from: releasesURL)
        } catch {
            DiagnosticsLog.log("Sikarugir engines: releases request failed - \(error.localizedDescription)")
            throw SikarugirEnginesRemoteError.requestFailed
        }
        guard (result.response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: result.data) as? [String: Any],
              let rawAssets = json["assets"] as? [[String: Any]] else {
            throw SikarugirEnginesRemoteError.requestFailed
        }

        let assets: [RemoteEngineAsset] = rawAssets.compactMap { asset in
            guard let fileName = asset["name"] as? String, fileName.hasSuffix(".tar.xz"),
                  let downloadURLString = asset["browser_download_url"] as? String,
                  let downloadURL = URL(string: downloadURLString),
                  let size = asset["size"] as? Int else {
                return nil
            }
            return RemoteEngineAsset(name: String(fileName.dropLast(".tar.xz".count)), downloadURL: downloadURL, sizeBytes: size)
        }
        guard !assets.isEmpty else { throw SikarugirEnginesRemoteError.noAssetsFound }
        return assets
    }

    /// Same preference `SikarugirEngine.recommendedEngineName()` already uses locally: the in-house
    /// Sikarugir build, newest version first - skipping 32-bit and the specialized "battle.net"
    /// variant, which aren't the general-purpose default.
    static func recommendedAsset(among assets: [RemoteEngineAsset]) -> RemoteEngineAsset? {
        let general = assets.filter {
            !$0.name.localizedCaseInsensitiveContains("32bit") && !$0.name.localizedCaseInsensitiveContains("battle.net")
        }
        let pool = general.isEmpty ? assets : general
        let sorted = pool.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        return sorted.first { $0.name.localizedCaseInsensitiveContains("sikarugir") } ?? sorted.first
    }

    /// Downloads straight into `~/Library/Application Support/Sikarugir/Engines/` - the same folder
    /// Sikarugir Creator itself uses, so an engine Playdock fetches is immediately usable by
    /// Sikarugir Creator too, and vice versa.
    @discardableResult
    static func download(_ asset: RemoteEngineAsset, progress: @escaping (String) -> Void) async throws -> String {
        progress("Downloading \(asset.name)…")
        let result: (url: URL, response: URLResponse)
        do {
            result = try await URLSession.shared.download(from: asset.downloadURL)
        } catch {
            throw SikarugirEnginesRemoteError.requestFailed
        }
        guard (result.response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SikarugirEnginesRemoteError.requestFailed
        }

        try FileManager.default.createDirectory(atPath: SikarugirEngine.sikarugirEnginesDir, withIntermediateDirectories: true)
        let destination = (SikarugirEngine.sikarugirEnginesDir as NSString).appendingPathComponent("\(asset.name).tar.xz")
        try? FileManager.default.removeItem(atPath: destination)
        try FileManager.default.moveItem(at: result.url, to: URL(fileURLWithPath: destination))
        progress("Downloaded \(asset.name).")
        DiagnosticsLog.log("Sikarugir engines: downloaded \(asset.name)")
        return asset.name
    }
}
