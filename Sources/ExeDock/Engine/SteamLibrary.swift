import Foundation

/// Scans ExeDock's Steam bottle for installed games the same way Steam itself tracks them - via
/// the `appmanifest_*.acf` files Steam writes into `steamapps/` for every installed app. ExeDock
/// never launches the executables it finds here directly (see `SteamGame.iconExePath`) - games are
/// always started through Steam via `-applaunch`, which is the only reliable way to pick up a
/// game's real launch arguments and prerequisites.
enum SteamLibrary {
    /// Steam's own shared runtime payloads that show up as "apps" in steamapps/ but aren't games.
    private static let ignoredNames: Set<String> = ["steamworks common redistributables"]
    private static let ignoredExeHints = [
        "unins", "uninstall", "setup", "updater", "crashhandler", "crashreport",
        "vconsole", "easyanticheat", "battleye", "vcredist", "dxsetup", "dotnet",
    ]

    private static var steamAppsPath: String {
        (SteamInstaller.steamBottle.driveCPath as NSString)
            .appendingPathComponent("Program Files (x86)/Steam/steamapps")
    }

    static func installedGames() -> [SteamGame] {
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

                return SteamGame(appID: appID, name: name, installDir: installDir, iconExePath: iconExecutable(inFolder: gameFolder))
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
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: folder) else { return nil }
        var candidates: [(path: String, size: Int)] = []
        for case let relativePath as String in enumerator {
            if enumerator.level > 5 {
                enumerator.skipDescendants()
                continue
            }
            guard relativePath.lowercased().hasSuffix(".exe") else { continue }
            let name = (relativePath as NSString).lastPathComponent.lowercased()
            guard !ignoredExeHints.contains(where: { name.contains($0) }) else { continue }
            let fullPath = (folder as NSString).appendingPathComponent(relativePath)
            let attrs = try? fm.attributesOfItem(atPath: fullPath)
            let size = (attrs?[.size] as? Int) ?? 0
            candidates.append((fullPath, size))
        }
        return candidates.max(by: { $0.size < $1.size })?.path
    }
}
