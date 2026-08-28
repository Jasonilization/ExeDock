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
    /// caches, and returns the result.
    func recommendation(for game: SteamGame, forceRefresh: Bool = false) async -> CompatibilityRecommendation {
        if !forceRefresh, let cached = CompatibilityCache.load(appID: game.appID) {
            return cached
        }

        let allSources = sources
        let reports = await withTaskGroup(of: [CompatibilityReport].self) { group in
            for source in allSources {
                group.addTask { await source.fetchReports(for: game) }
            }
            var combined: [CompatibilityReport] = []
            for await result in group { combined.append(contentsOf: result) }
            return combined
        }

        let recommendation = CompatibilityAggregator.aggregate(reports: reports)
        CompatibilityCache.save(recommendation, appID: game.appID)
        return recommendation
    }
}
