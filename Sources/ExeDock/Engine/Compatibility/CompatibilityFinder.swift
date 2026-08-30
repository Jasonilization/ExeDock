import Foundation

/// Orchestrates every `CompatibilitySource` in parallel, aggregates the results, and caches them -
/// the single entry point the UI calls. Adding a new source later is just adding one more
/// conformance to `sources`.
actor CompatibilityFinder {
    static let shared = CompatibilityFinder()

    private let sources: [CompatibilitySource] = [
        AppleGamingWikiSource(),
        GitHubCompatibilitySource(),
        LocalHistorySource(),
    ]

    /// Returns the cached recommendation immediately unless `forceRefresh` is set or nothing's
    /// cached yet, in which case it fetches fresh evidence from every source at once, aggregates,
    /// caches, and returns the result. Generalized from a concrete `SteamGame` to a plain id/name
    /// pair so a custom (manually-imported) game can use the exact same pipeline.
    func recommendation(id: String, name: String, forceRefresh: Bool = false) async -> CompatibilityRecommendation {
        if !forceRefresh, let cached = CompatibilityCache.load(appID: id) {
            return cached
        }

        let allSources = sources
        let reports = await withTaskGroup(of: [CompatibilityReport].self) { group in
            for source in allSources {
                group.addTask { await source.fetchReports(id: id, name: name) }
            }
            var combined: [CompatibilityReport] = []
            for await result in group { combined.append(contentsOf: result) }
            return combined
        }

        let recommendation = CompatibilityAggregator.aggregate(reports: reports)
        CompatibilityCache.save(recommendation, appID: id)
        return recommendation
    }

    /// Convenience for the common Steam case.
    func recommendation(for game: SteamGame, forceRefresh: Bool = false) async -> CompatibilityRecommendation {
        await recommendation(id: game.appID, name: game.name, forceRefresh: forceRefresh)
    }
}
