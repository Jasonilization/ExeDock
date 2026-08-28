import Foundation

struct RunningProcessInfo: Equatable {
    let pid: Int32
    let startedAt: Date
}

/// Best-effort detection of whether a specific Steam game's process is actually running right now,
/// and since when - Playdock has no real Wine/Steam IPC hook into a game Steam itself launched, so
/// this greps `ps` for a command line containing the game's own install-dir fragment. Windows
/// processes running under Wine show their full Windows command line in `ps` output - confirmed
/// live earlier this session (ordinary `ps aux` lines like
/// `C:\Program Files (x86)\Steam\bin\cef\...\steamwebhelper.exe`) - so this is real, not
/// theoretical, but it's still a heuristic: two games sharing an install-dir fragment could
/// collide, and a game launched under an unexpected child-process name won't be seen.
///
/// One shared poller (not four separate ones) backs the live game-card status, the launch
/// overlay's dismiss trigger, dashboard theming, and Inspect mode. `syncWatchedGames` is called
/// once from the dashboard with whatever's currently in `model.steamGames`, so this only polls
/// while there's actually something worth watching (nothing running while Game Mode is locked, or
/// before the library has loaded).
@MainActor
final class RunningGameTracker: ObservableObject {
    static let shared = RunningGameTracker()

    @Published private(set) var runningGames: [String: RunningProcessInfo] = [:]

    private var pollTask: Task<Void, Never>?
    private var watchedGames: [String: String] = [:] // appID -> installDir
    private var knownStartTimes: [String: Date] = [:]

    private init() {}

    /// Replaces the full watch list - call with the dashboard's current game list. Games no longer
    /// present are dropped from `runningGames` immediately rather than waiting for the next poll.
    func syncWatchedGames(_ games: [SteamGame]) {
        let newWatch = Dictionary(uniqueKeysWithValues: games.map { ($0.appID, $0.installDir) })
        watchedGames = newWatch
        runningGames = runningGames.filter { newWatch[$0.key] != nil }
        knownStartTimes = knownStartTimes.filter { newWatch[$0.key] != nil }

        if watchedGames.isEmpty {
            pollTask?.cancel()
            pollTask = nil
        } else {
            ensurePolling()
        }
    }

    private func ensurePolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func pollOnce() async {
        let targets = watchedGames
        guard !targets.isEmpty else { return }
        let matches = await Task.detached(priority: .utility) {
            Self.findRunningPIDs(for: targets)
        }.value
        guard !Task.isCancelled else { return }

        for (appID, _) in targets {
            if let pid = matches[appID] {
                let startedAt = knownStartTimes[appID] ?? Date()
                knownStartTimes[appID] = startedAt
                runningGames[appID] = RunningProcessInfo(pid: pid, startedAt: startedAt)
            } else {
                runningGames.removeValue(forKey: appID)
                knownStartTimes.removeValue(forKey: appID)
            }
        }
    }

    /// Off the main actor: shells out to `ps`, same pattern `ExeRunner`/`SikarugirEngine` already
    /// use for `tar`/`cp`. `installDir` (e.g. "Hollow Knight") is more unique than the exe's own
    /// basename, so it's what's matched against each line's command text.
    nonisolated private static func findRunningPIDs(for targets: [String: String]) -> [String: Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        var results: [String: Int32] = [:]
        for (appID, installDir) in targets {
            let backslashFragment = "steamapps\\common\\\(installDir)\\".lowercased()
            let slashFragment = "steamapps/common/\(installDir)/".lowercased()
            guard let line = lines.first(where: {
                let lower = $0.lowercased()
                return lower.contains(backslashFragment) || lower.contains(slashFragment)
            }) else { continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let spaceIndex = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[trimmed.startIndex..<spaceIndex]) else { continue }
            results[appID] = pid
        }
        return results
    }
}
