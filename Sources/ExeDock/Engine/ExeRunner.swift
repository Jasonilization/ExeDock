import Foundation
import AppKit

/// Launches Windows executables through the Sikarugir engine ExeDock reuses.
enum ExeRunner {
    static let logsDir = ("~/Library/Logs/ExeDock" as NSString).expandingTildeInPath

    /// `preferWrapperEngine`, when true and the target bottle isn't already a wrapper bottle (that
    /// case always uses that wrapper's own launcher, below), runs the exe with a real Sikarugir
    /// wrapper app's own bundled wine binary (see `SikarugirEngine.anyWrapperEngine`) instead of
    /// ExeDock's own separately-downloaded engine - still against `bottle`'s own prefix, just with a
    /// different engine reading it. Custom games use this - "just not use playdock's engine but
    /// sikarugir's, it is guaranteed to work on that one," per live feedback. Falls back to
    /// ExeDock's own engine if no Sikarugir wrapper app is actually installed to borrow one from.
    @discardableResult
    static func run(exePath: String, in bottle: Bottle, arguments: [String] = [], config: GameModeConfig = GameModeConfig(), engineName: String? = nil, preferWrapperEngine: Bool = false) async throws -> Process? {
        // A game living inside a *specific* Sikarugir wrapper's own bottle is launched through that
        // wrapper's own launcher binary (Contents/MacOS/Sikarugir - the same binary its
        // CFBundleExecutable points at, just invoked directly instead of through Finder/
        // LaunchServices) using its own real, documented CLI: `sikarugir run <file> [flags]` -
        // confirmed by reading that binary's own embedded `strings` output, which includes its
        // full `Usage: sikarugir [options] ...` help text verbatim (down to the literal source
        // file name, `Sikarugir/SikarugirCliAdapter.swift`) - not a guess. Critically, that same
        // help text also documents `(no options)` as "run (or debug) main bat/msi/exe file" - i.e.
        // launching the wrapper with no arguments at all runs whatever it's already configured for
        // by default, completely unrelated to which specific custom game was actually clicked in
        // Playdock. That's confirmed as the real, exact cause of a real bug: launching "Subliminal"
        // instead started a stale, already-crashed "Dreamcore" process, because that happened to be
        // this particular bottle's own configured default. Passing `run <exePath>` explicitly,
        // every single launch, is what "should change and load the exe path to the right everytime
        // for what game launched" actually requires - not just opening the app and hoping.
        if case .sikarugirWrapper(let appPath) = bottle.kind {
            let launcherBinary = appPath + "/Contents/MacOS/Sikarugir"
            guard FileManager.default.isExecutableFile(atPath: launcherBinary) else {
                // Its own launcher isn't where expected - opening the app is still better than a
                // hard failure, even though it can't target the right exe this way.
                try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: NSWorkspace.OpenConfiguration())
                return nil
            }

            try? FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let baseName = (exePath as NSString).lastPathComponent
            let logPath = (logsDir as NSString).appendingPathComponent("\(baseName)-\(timestamp).log")
            FileManager.default.createFile(atPath: logPath, contents: nil)
            let logHandle = FileHandle(forWritingAtPath: logPath)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: launcherBinary)
            process.arguments = ["run", exePath] + arguments
            process.currentDirectoryURL = URL(fileURLWithPath: (exePath as NSString).deletingLastPathComponent)
            process.standardOutput = logHandle
            process.standardError = logHandle
            try process.run()
            return process
        }

        let wrapperEngine = preferWrapperEngine ? SikarugirEngine.anyWrapperEngine() : nil
        let wineBinary = try wrapperEngine?.wineBinary ?? SikarugirEngine.wineBinaryPath(engineName: engineName ?? config.engineName)
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
        // Matches what actually double-clicking an exe in Explorer does: run with the exe's own
        // folder as the working directory. A real, confirmed cause of custom games (Unreal Engine
        // titles especially, which often resolve their own Content/Saved folders relative to the
        // process's working directory, not just the exe's location) launching and immediately
        // quitting through ExeDock - without this, the wine process inherited ExeDock's own working
        // directory instead, which the game's own asset-loading code was never expecting.
        process.currentDirectoryURL = URL(fileURLWithPath: (exePath as NSString).deletingLastPathComponent)
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.prefixPath
        if let wrapperEngine {
            // Must be paired with the *same* app's own lib/Frameworks - mixing a wrapper's wine
            // binary with ExeDock's own downloaded engine's shared libraries risks a broken,
            // version-mismatched mix.
            env["DYLD_FALLBACK_LIBRARY_PATH"] = "\(wrapperEngine.frameworksDir):\(wrapperEngine.libDir)"
        } else {
            for (key, value) in try SikarugirEngine.runtimeEnvironment(engineName: engineName ?? config.engineName) { env[key] = value }
        }
        for (key, value) in config.environment { env[key] = value }
        process.environment = env
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        return process
    }
}
