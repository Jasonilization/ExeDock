import Foundation

/// Turns this device's own `LocalOutcomeTracker` history into a `CompatibilityReport`, so "you've
/// launched this N times with D3DMetal and it never errored" flows through the exact same
/// aggregation path as web evidence, per the request to use local history as supplementary
/// evidence. Deliberately weak on its own: it's exactly one source name, so
/// `CompatibilityAggregator`'s independent-source requirement means local history alone can never
/// produce high confidence - it can only reinforce (or fail to reinforce) what other sources say.
struct LocalHistorySource: CompatibilitySource {
    let name = "This Mac's launch history"

    func fetchReports(for game: SteamGame) async -> [CompatibilityReport] {
        let records = LocalOutcomeTracker.records(for: game.appID)
        guard !records.isEmpty else { return [] }

        let successfulConfigs = records.filter { !$0.launchErrored }.map(\.config)
        let errorCount = records.count - successfulConfigs.count
        guard let mostCommon = mostCommonConfig(in: successfulConfigs) else { return [] }

        var settings = DetectedSettings()
        settings.d3dMetal = mostCommon.d3dMetal
        settings.dxvk = mostCommon.dxvk
        settings.dxmt = mostCommon.dxmt
        settings.moltenVKCX = mostCommon.moltenVKCX
        settings.wineESync = mostCommon.wineESync
        settings.wineMSync = mostCommon.wineMSync

        var excerpt = "Launched \(successfulConfigs.count) time(s) on this Mac with this configuration without an immediate error."
        if errorCount > 0 {
            excerpt += " \(errorCount) other attempt(s) with a different configuration failed to start."
        }
        return [CompatibilityReport(sourceName: name, sourceURL: "", excerpt: excerpt, settings: settings)]
    }

    private func mostCommonConfig(in configs: [GameModeConfig]) -> GameModeConfig? {
        guard !configs.isEmpty else { return nil }
        var counts: [GameModeConfig: Int] = [:]
        for config in configs { counts[config, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
