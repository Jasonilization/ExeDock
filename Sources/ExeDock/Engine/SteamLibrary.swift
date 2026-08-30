import Foundation

/// Scans a Steam library for installed games the same way Steam itself tracks them - via the
/// `appmanifest_*.acf` files Steam writes into `steamapps/` for every installed app. Used for both
/// ExeDock's own Windows Steam bottle and, separately, the real macOS Steam client's own library
/// (see `installedNativeMacGames()`) - the manifest format is identical either way.
enum SteamLibrary {
    /// Steam's own shared runtime payloads that show up as "apps" in steamapps/ but aren't games.
    private static let ignoredNames: Set<String> = ["steamworks common redistributables"]

    private static var wineBottleSteamAppsPath: String {
        (SteamInstaller.steamBottle.driveCPath as NSString)
            .appendingPathComponent("Program Files (x86)/Steam/steamapps")
    }

    static func installedGames() -> [SteamGame] {
        installedGames(inSteamAppsPath: wineBottleSteamAppsPath, source: .wineBottle, idPrefix: nil)
    }

    private static let nativeMacSteamRoot = ("~/Library/Application Support/Steam" as NSString).expandingTildeInPath

    /// Every game installed through the real, separately-installed macOS Steam client - a
    /// completely different Steam install from ExeDock's own Windows one, confirmed live to exist
    /// side by side on the same Mac (`~/Library/Application Support/Steam`). Every library folder
    /// Steam itself knows about is scanned, not just the default one, by reading the exact same
    /// `libraryfolders.vdf` format Steam's own client writes - so a second library folder (an
    /// external drive, say) is picked up automatically too.
    static func installedNativeMacGames() -> [SteamGame] {
        nativeMacSteamAppsPaths()
            .flatMap { installedGames(inSteamAppsPath: $0, source: .nativeMac, idPrefix: "MAC-") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func nativeMacSteamAppsPaths() -> [String] {
        let defaultPath = (nativeMacSteamRoot as NSString).appendingPathComponent("steamapps")
        let vdfPath = (defaultPath as NSString).appendingPathComponent("libraryfolders.vdf")
        guard let text = try? String(contentsOfFile: vdfPath, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: "\"path\"\\s+\"([^\"]*)\"") else {
            return FileManager.default.fileExists(atPath: defaultPath) ? [defaultPath] : []
        }
        let range = NSRange(text.startIndex..., in: text)
        let paths = regex.matches(in: text, range: range).compactMap { match -> String? in
            guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
            // Steam escapes its own path separators in this file (e.g. "\\" for a literal "/") -
            // undo that before treating it as a real filesystem path.
            let raw = String(text[valueRange]).replacingOccurrences(of: "\\\\", with: "/")
            return (raw as NSString).appendingPathComponent("steamapps")
        }
        return paths.isEmpty ? [defaultPath] : paths
    }

    private static func installedGames(inSteamAppsPath steamAppsPath: String, source: SteamGameSource, idPrefix: String?) -> [SteamGame] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: steamAppsPath) else { return [] }
        let commonPath = (steamAppsPath as NSString).appendingPathComponent("common")

        let games: [SteamGame] = entries
            .filter { $0.hasPrefix("appmanifest_") && $0.hasSuffix(".acf") }
            .compactMap { manifestName -> SteamGame? in
                let manifestPath = (steamAppsPath as NSString).appendingPathComponent(manifestName)
                guard let text = try? String(contentsOfFile: manifestPath, encoding: .utf8) else { return nil }
                guard let appID = value(for: "appid", in: text),
                      let name = value(for: "name", in: text),
                      let installDir = value(for: "installdir", in: text),
                      !ignoredNames.contains(name.lowercased()) else { return nil }

                // Steam sets bit 0x4 in StateFlags once an app is fully installed and playable -
                // without this check, a game whose download is still in progress (its folder
                // already exists, just incomplete) would show up as launchable. Treat a missing/
                // unparseable StateFlags leniently (include it) rather than hiding a real game.
                if let stateFlags = value(for: "StateFlags", in: text).flatMap({ Int($0) }), stateFlags & 0x4 == 0 {
                    return nil
                }

                let gameFolder = (commonPath as NSString).appendingPathComponent(installDir)
                guard fm.fileExists(atPath: gameFolder) else { return nil }

                let sizeOnDisk = value(for: "SizeOnDisk", in: text).flatMap { Int64($0) }
                let buildID = value(for: "buildid", in: text)
                let lastUpdated = value(for: "LastUpdated", in: text).flatMap { TimeInterval($0) }
                    .flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }

                return SteamGame(
                    appID: (idPrefix ?? "") + appID, name: name, installDir: installDir,
                    installFolderPath: gameFolder,
                    iconExePath: source == .wineBottle ? iconExecutable(inFolder: gameFolder) : nil,
                    sizeOnDisk: (sizeOnDisk ?? 0) > 0 ? sizeOnDisk : nil,
                    buildID: (buildID != "0") ? buildID : nil,
                    lastUpdated: lastUpdated,
                    source: source
                )
            }
        return games.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Pulls a top-level `"key"    "value"` pair out of an ACF/VDF manifest. Steam only ever nests
    /// `appid`/`name`/`installdir` once, right under `AppState`, so a first-match regex is enough -
    /// no need for a full VDF parser for the handful of fields ExeDock actually reads.
    private static func value(for key: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\"\(key)\"\\s+\"([^\"]*)\"", options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange])
    }

    /// Best-effort search for an executable to grab an icon from. Source-engine-style games nest
    /// their real binary several folders deep (e.g. `game/bin/win64/`), deeper than a typical
    /// Program Files install, so this looks further down than `CDriveScanner` does.
    private static func iconExecutable(inFolder folder: String) -> String? {
        ExecutableHeuristics.bestGuessExecutable(inFolder: folder, maxDepth: 5)
    }
}
