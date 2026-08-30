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
