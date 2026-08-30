import Foundation

/// Launches Windows executables through the Sikarugir engine ExeDock reuses.
enum ExeRunner {
    static let logsDir = ("~/Library/Logs/ExeDock" as NSString).expandingTildeInPath

    @discardableResult
    static func run(exePath: String, in bottle: Bottle, arguments: [String] = [], extraEnvironment: [String: String] = [:], engineName: String? = nil) throws -> Process {
        // Anything running inside a *specific* Sikarugir wrapper's own bottle runs under that
        // wrapper's own bundled engine, not ExeDock's separately-managed one - see
        // `SikarugirEngine.wrapperEngine`'s own doc comment for why that's not just a nicety.
        let wineBinary: String
        let wrapperLibraryPath: String?
        if case .sikarugirWrapper(let appPath) = bottle.kind, let wrapperEngine = SikarugirEngine.wrapperEngine(appPath: appPath) {
            wineBinary = wrapperEngine.wineBinary
            wrapperLibraryPath = "\(wrapperEngine.frameworksDir):\(wrapperEngine.libDir)"
        } else {
            wineBinary = try SikarugirEngine.wineBinaryPath(engineName: engineName)
            wrapperLibraryPath = nil
        }
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
        if let wrapperLibraryPath {
            env["DYLD_FALLBACK_LIBRARY_PATH"] = wrapperLibraryPath
        } else {
            for (key, value) in try SikarugirEngine.runtimeEnvironment(engineName: engineName) { env[key] = value }
        }
        for (key, value) in extraEnvironment { env[key] = value }
        process.environment = env
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        return process
    }
}
