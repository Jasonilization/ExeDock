import Foundation

/// A place Playdock can pull compatibility evidence from. The modularity point of this whole
/// system: adding a new source later (a forum, a curated CSV, whatever) is just one more
/// conformance added to the array `CompatibilityFinder` iterates - nothing else changes.
protocol CompatibilitySource: Sendable {
    var name: String { get }
    func fetchReports(for game: SteamGame) async -> [CompatibilityReport]
}
