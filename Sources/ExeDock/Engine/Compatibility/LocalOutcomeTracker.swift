import Foundation

struct LaunchOutcomeRecord: Codable {
    let appID: String
    let config: GameModeConfig
    let timestamp: Date
    let launchErrored: Bool
}

/// A small local record of "this config was used to launch this game, and whether it errored
/// immediately" - per-game history that feeds `LocalHistorySource` as supplementary evidence, and
/// (later) the Experiment wizard's results. Honest limit, documented at every call site that reads
/// this: Playdock can only ever know whether the launch *started* without erroring, not whether the
/// game kept working - same limitation that sank the old automatic launch-retry ladder.
enum LocalOutcomeTracker {
    private static let path = ("~/Library/Application Support/ExeDock/LaunchOutcomes.json" as NSString).expandingTildeInPath
    /// Keeps the file small and the read/tally cost trivial - only recent history is useful signal
    /// anyway (an old outcome under a long-since-changed engine version says little).
    private static let maxStoredRecords = 500

    static func record(appID: String, config: GameModeConfig, launchErrored: Bool) {
        var records = loadAll()
        records.append(LaunchOutcomeRecord(appID: appID, config: config, timestamp: Date(), launchErrored: launchErrored))
        save(Array(records.suffix(maxStoredRecords)))
    }

    static func records(for appID: String) -> [LaunchOutcomeRecord] {
        loadAll().filter { $0.appID == appID }
    }

    private static func loadAll() -> [LaunchOutcomeRecord] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        return (try? JSONDecoder().decode([LaunchOutcomeRecord].self, from: data)) ?? []
    }

    private static func save(_ records: [LaunchOutcomeRecord]) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
