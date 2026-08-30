import Foundation

/// Launches Windows executables through the Sikarugir engine ExeDock reuses.
enum ExeRunner {
    static let logsDir = ("~/Library/Logs/ExeDock" as NSString).expandingTildeInPath

    @discardableResult
    static func run(exePath: String, in bottle: Bottle, arguments: [String] = [], config: GameModeConfig = GameModeConfig(), engineName: String? = nil) throws -> Process {
        // Always ExeDock's own managed engine - even for something living inside a *specific*
        // Sikarugir wrapper's own bottle. See `SikarugirEngine.rendererEnvironment`'s doc comment for
        // the full, evidence-based reasoning: an earlier attempt at this instead forced the
        // wrapper's own bundled wine binary, on the theory that a version/fork mismatch
        // (`wine --version` showed a real difference) was the whole problem. It wasn't - a real
        // launch log against that binary showed the game loading fully (assets, audio, Steam SDK)
        // and only then failing to create a D3D11 device, because that specific older
        // CrossOver-derived build needs its DirectX-Metal support wired up via its own closed,
        // folder-based DLL-override mechanism (confirmed by inspecting its own binary's strings:
        // `CX_D3DMETALPATH`, per-renderer folders under its own `Contents/Frameworks/renderer/`) -
        // not the plain `D3DMETAL=1` env var ExeDock's own engine genuinely honors directly (that's
        // the whole premise `GameModeConfig` is built on). The bottle's *prefix* (its installed
        // game files, registry, save data) is the only thing that actually needs to be "that
        // wrapper's own" - which wine binary reads it is a separate, swappable choice, and wine
        // itself safely migrates a prefix last touched by a different wine build (confirmed live:
        // "wine: configuration ... has been updated" is wine's own normal, expected message for
        // exactly this, not an error).
        let resolvedEngineName = engineName ?? config.engineName
        let wineBinary = try SikarugirEngine.wineBinaryPath(engineName: resolvedEngineName)
        if !bottle.isReadOnly {
            try BottleManager.shared.ensureInitialized(bottle, wineBinary: wineBinary)
        }

        try? FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let baseName = (exePath as NSString).lastPathComponent
        let logPath = (logsDir as NSString).appendingPathComponent("\(baseName)-\(timestamp).log")
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let logHandle = FileHandle(forWritingAtPath: logPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineBinary)
        process.arguments = [exePath] + arguments
        // Matches what actually double-clicking an exe in Explorer (or a Sikarugir wrapper app's
        // own launch script) does: run with the exe's own folder as the working directory. A real,
        // confirmed cause of custom games (Unreal Engine titles especially, which often resolve
        // their own Content/Saved folders relative to the process's working directory, not just the
        // exe's location) launching and immediately quitting through ExeDock - without this, the
        // wine process inherited ExeDock's own working directory instead, which the game's own
        // asset-loading code was never expecting.
        process.currentDirectoryURL = URL(fileURLWithPath: (exePath as NSString).deletingLastPathComponent)
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.prefixPath
        for (key, value) in try SikarugirEngine.runtimeEnvironment(engineName: resolvedEngineName) { env[key] = value }

        // A wrapper bottle's own DirectX-backend/sync settings (from its Info.plist) replace
        // ExeDock's own per-game GameModeConfig entirely rather than layering on top of it - "my
        // bottle in subliminal has great settings, use that as default for custom," per live
        // feedback. Either way, `rendererEnvironment` (not the config's own bare `.environment`)
        // is what actually turns the chosen toggle into something wine honors - see its own doc
        // comment for why that distinction is real, not cosmetic.
        let effectiveConfig: GameModeConfig
        if case .sikarugirWrapper(let appPath) = bottle.kind, let wrapperConfig = SikarugirEngine.wrapperConfig(appPath: appPath) {
            effectiveConfig = wrapperConfig
        } else {
            effectiveConfig = config
        }
        let frameworksDir = (try? SikarugirEngine.ensureFrameworksAvailable()) ?? SikarugirEngine.exeDockFrameworksDir
        for (key, value) in SikarugirEngine.rendererEnvironment(frameworksDir: frameworksDir, config: effectiveConfig) { env[key] = value }
        process.environment = env
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        return process
    }
}
