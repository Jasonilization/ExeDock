import Foundation

/// Reads the currently logged-in Steam account straight out of the local Steam bottle's own config
/// files - the same approach `SteamLibrary` uses for the game list. Nothing here ever talks to the
/// network or needs an API key: `config/loginusers.vdf` for the name, `config/avatarcache/` for a
/// locally cached avatar image Steam already downloaded for its own UI.
enum SteamProfileReader {
    private static var configPath: String {
        (SteamInstaller.steamBottle.driveCPath as NSString)
            .appendingPathComponent("Program Files (x86)/Steam/config")
    }

    static func currentProfile() -> SteamProfile? {
        let loginUsersPath = (configPath as NSString).appendingPathComponent("loginusers.vdf")
        guard let text = try? String(contentsOfFile: loginUsersPath, encoding: .utf8) else { return nil }

        let accounts = parseAccountBlocks(in: text)
        // Prefer whichever account Steam itself last used - only meaningful once more than one
        // account has ever signed in on this bottle. With just one account, there's nothing to
        // pick between.
        let chosen = accounts.first { $0.value(for: "MostRecent") == "1" } ?? accounts.first
        guard let account = chosen, let personaName = account.value(for: "PersonaName") else { return nil }

        let avatarCandidate = (configPath as NSString).appendingPathComponent("avatarcache/\(account.steamID64).png")
        let avatarPath = FileManager.default.fileExists(atPath: avatarCandidate) ? avatarCandidate : nil

        return SteamProfile(
            steamID64: account.steamID64,
            personaName: personaName,
            accountName: account.value(for: "AccountName") ?? personaName,
            avatarPath: avatarPath
        )
    }

    private struct AccountBlock {
        let steamID64: String
        let body: String

        func value(for key: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: "\"\(key)\"\\s+\"([^\"]*)\"", options: .caseInsensitive) else {
                return nil
            }
            let range = NSRange(body.startIndex..., in: body)
            guard let match = regex.firstMatch(in: body, range: range), let valueRange = Range(match.range(at: 1), in: body) else {
                return nil
            }
            return String(body[valueRange])
        }
    }

    /// `loginusers.vdf` nests one flat (no further braces) block per account, keyed by its 17-digit
    /// SteamID64: `"<id>" { "AccountName" "…" "PersonaName" "…" … }`.
    private static func parseAccountBlocks(in text: String) -> [AccountBlock] {
        guard let regex = try? NSRegularExpression(pattern: "\"(\\d{17})\"\\s*\\{([^{}]*)\\}") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match -> AccountBlock? in
            guard let idRange = Range(match.range(at: 1), in: text),
                  let bodyRange = Range(match.range(at: 2), in: text) else { return nil }
            return AccountBlock(steamID64: String(text[idRange]), body: String(text[bodyRange]))
        }
    }
}
