import Foundation

/// The locally logged-in Steam account, read straight out of ExeDock's own Steam bottle - no
/// network call, no API key, nothing leaves the Mac. See `SteamProfileReader`.
struct SteamProfile: Equatable {
    let steamID64: String
    let personaName: String
    let accountName: String
    /// Path to a locally cached avatar image, if Steam has one on disk for this account.
    let avatarPath: String?
}
