import Foundation

/// Launches a game (or Steam itself) with automatic fallback: if the process ExeDock started exits
/// with a non-zero status within a few seconds - a strong signal Wine failed to even get it running,
/// rather than it simply running fine in the background - this tries a short ladder of different
/// engine/graphics combinations before giving up and surfacing an error.
///
/// This only helps for processes ExeDock spawns and fully controls. When Steam is already running,
/// `-applaunch` just messages the existing Steam process and returns almost immediately - the actual
/// game is then started by that already-running process, using whatever environment IT was launched
/// with, not this call's. The ladder still helps get Steam itself running reliably, and helps
/// directly-run (non-Steam) executables recover from a bad engine/graphics combination.
enum GameLauncher {
    struct Attempt {
        let config: GameModeConfig
        /// Short, human-readable description of what's different about this attempt, used in the
        /// "trying X…" status message shown before it runs.
        let label: String
    }

    /// A short, bounded set of things to try, most-likely-to-work first: the caller's own saved
    /// settings, then progressively more conservative fallbacks. Kept short (≤4) so a total failure
    /// still resolves in well under a minute.
    static func ladder(from base: GameModeConfig) -> [Attempt] {
        var attempts: [Attempt] = [Attempt(config: base, label: "your saved settings")]

        var toggledDXVK = base
        toggledDXVK.dxvk.toggle()
        attempts.append(Attempt(config: toggledDXVK, label: toggledDXVK.dxvk ? "DXVK enabled" : "DXVK disabled"))

        let otherEngines = SikarugirEngine.availableEngineNames().filter { $0 != base.engineName }
        if let alternate = otherEngines.first {
            var altConfig = base
            altConfig.engineName = alternate
            attempts.append(Attempt(config: altConfig, label: "the \(alternate) engine"))
        }

        var safeMode = base
        safeMode.dxvk = false
        safeMode.dxmt = false
        safeMode.d3dMetal = true
        safeMode.moltenVKCX = false
        safeMode.wineESync = false
        safeMode.wineMSync = false
        if safeMode != attempts.last?.config {
            attempts.append(Attempt(config: safeMode, label: "compatibility settings"))
        }

        return attempts
    }

    /// True if `process` exited with a non-zero status within `grace` seconds - i.e. it failed fast
    /// rather than actually starting. A process still running past the grace period (or one that
    /// exited 0 quickly, e.g. Steam.exe handing off to an already-running client) counts as success.
    ///
    /// Polls `isRunning` on a short interval instead of calling the blocking `waitUntilExit()` -
    /// a launched game can keep running for hours, and blocking on that would pin one of Swift's
    /// small, fixed pool of cooperative threads for the entire session instead of returning once the
    /// grace period is up.
    static func failedQuickly(_ process: Process, grace: TimeInterval = 4) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(grace))
        while ContinuousClock.now < deadline {
            if !process.isRunning {
                return process.terminationStatus != 0
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }
}
