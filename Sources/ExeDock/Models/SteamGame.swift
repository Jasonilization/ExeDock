import Foundation

/// A game ExeDock found installed in the Steam library inside its own Steam bottle.
struct SteamGame: Identifiable, Hashable {
    let appID: String
    let name: String
    let installDir: String
    /// Best-effort path to an executable inside the game's install folder, used only to look up a
    /// recognizable icon. ExeDock never runs this directly - games are always launched through
    /// Steam itself (`-applaunch`), since only Steam knows a game's real launch arguments and
    /// prerequisites, and some titles (anti-cheat games especially) require launching that way.
    let iconExePath: String?
    /// Bytes on disk, from the manifest's `SizeOnDisk` - shown on the game's card.
    let sizeOnDisk: Int64?
    /// Steam's own internal build number for the installed copy, from the manifest's `buildid` -
    /// the closest thing to a "version" Steam tracks locally.
    let buildID: String?
    /// Unix timestamp of the last update, from the manifest's `LastUpdated`.
    let lastUpdated: Date?

    var id: String { appID }
}
