import Foundation

/// A place Playdock can pull compatibility evidence from. The modularity point of this whole
/// system: adding a new source later (a forum, a curated CSV, whatever) is just one more
/// conformance added to the array `CompatibilityFinder` iterates - nothing else changes.
protocol CompatibilitySource: Sendable {
    var name: String { get }
    /// `id` only matters to `LocalHistorySource` (it keys this Mac's own launch history); the
    /// public web sources only ever look at `name`. Generalized from a concrete `SteamGame` so a
    /// custom (manually-imported) game can be looked up too, using its own id and display name.
    func fetchReports(id: String, name: String) async -> [CompatibilityReport]
}
