import Foundation

/// Public store metadata for a game - description, artwork, genres, release date, and rating - used
/// to make a game's card (and the richer Game Detail view) feel like part of a real Steam dashboard
/// instead of a bare file-launcher row. All of it comes from the one `appdetails` call
/// `SteamStoreInfoCache` already makes - no extra network round trip for the extra fields.
struct SteamStoreInfo: Codable, Equatable {
    let shortDescription: String?
    /// Path to a locally cached copy of the header image, if one downloaded successfully.
    let headerImagePath: String?
    /// Path to a locally cached copy of the wide background/hero art, if one downloaded
    /// successfully - meant for a full-screen detail view backdrop, not the small grid card.
    var backgroundImagePath: String?
    var genres: [String] = []
    var releaseDate: String?
    var developers: [String] = []
    var publishers: [String] = []
    var metacriticScore: Int?
    var metacriticURL: String?
    var categories: [String] = []

    /// Decodes leniently so cache files written before these fields existed (just
    /// `shortDescription`/`headerImagePath`) still load fine - they simply come back with the new
    /// fields empty, and get filled in on the next network fetch rather than failing to decode at
    /// all (which would otherwise just force a silent, harmless re-fetch anyway).
    init(shortDescription: String?, headerImagePath: String?, backgroundImagePath: String? = nil,
         genres: [String] = [], releaseDate: String? = nil, developers: [String] = [], publishers: [String] = [],
         metacriticScore: Int? = nil, metacriticURL: String? = nil, categories: [String] = []) {
        self.shortDescription = shortDescription
        self.headerImagePath = headerImagePath
        self.backgroundImagePath = backgroundImagePath
        self.genres = genres
        self.releaseDate = releaseDate
        self.developers = developers
        self.publishers = publishers
        self.metacriticScore = metacriticScore
        self.metacriticURL = metacriticURL
        self.categories = categories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        headerImagePath = try container.decodeIfPresent(String.self, forKey: .headerImagePath)
        backgroundImagePath = try container.decodeIfPresent(String.self, forKey: .backgroundImagePath)
        genres = try container.decodeIfPresent([String].self, forKey: .genres) ?? []
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        developers = try container.decodeIfPresent([String].self, forKey: .developers) ?? []
        publishers = try container.decodeIfPresent([String].self, forKey: .publishers) ?? []
        metacriticScore = try container.decodeIfPresent(Int.self, forKey: .metacriticScore)
        metacriticURL = try container.decodeIfPresent(String.self, forKey: .metacriticURL)
        categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
    }
}
