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

    var id: String { appID }
}
