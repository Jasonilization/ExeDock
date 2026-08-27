import Foundation

/// Public store metadata for a game - a short description and header art - used to make a game's
/// card feel like part of a real Steam dashboard instead of a bare file-launcher row.
struct SteamStoreInfo: Codable, Equatable {
    let shortDescription: String?
    /// Path to a locally cached copy of the header image, if one downloaded successfully.
    let headerImagePath: String?
}
