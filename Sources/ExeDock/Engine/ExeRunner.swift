import Foundation

/// Launches Windows executables through the Sikarugir engine ExeDock reuses.
enum ExeRunner {
    static let logsDir = ("~/Library/Logs/ExeDock" as NSString).expandingTildeInPath

    // Every process this launches used to be fired with `Process.run()` and the handle thrown away,
    // so ExeDock had zero visibility into what it had started and no way to stop it. The only way to
    // recover a hung launch (a game stuck mid-startup) was Force Quitting ExeDock or killing the wine
    // process from Activity Monitor - a hard SIGKILL that never lets wineserver shut down cleanly,
    // leaving it and every helper process it spawned (winedevice.exe, services.exe, …) orphaned under
    // launchd, burning CPU/battery indefinitely with nothing left to tell them to exit. Tracking the
    // process here is what makes `forceQuit(bottle:)` below possible.
    private static let stateLock = NSLock()
    private static var runningProcesses: [String: Process] = [:]

    static func isRunning(bottle: Bottle) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return runningProcesses[bottle.id] != nil
    }

    @discardableResult
    static func run(exePath: String, in bottle: Bottle, arguments: [String] = [], extraEnvironment: [String: String] = [:], onExit: @escaping (Int32) -> Void = { _ in }) throws -> Process {
        let wineBinary = try SikarugirEngine.wineBinaryPath()
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
        for (key, value) in try SikarugirEngine.runtimeEnvironment() { env[key] = value }
        for (key, value) in extraEnvironment { env[key] = value }
        process.environment = env
        process.standardOutput = logHandle
        process.standardError = logHandle

        stateLock.lock()
        runningProcesses[bottle.id] = process
        stateLock.unlock()

        process.terminationHandler = { finished in
            stateLock.lock()
            if runningProcesses[bottle.id] === finished { runningProcesses[bottle.id] = nil }
            stateLock.unlock()
            onExit(finished.terminationStatus)
        }

        try process.run()
        return process
    }

    /// Cleanly tears down everything running inside a bottle's Wine session - the launched process,
    /// plus wineserver and every helper process it spawned - via `wineserver -k`, scoped to that
    /// bottle's own WINEPREFIX (other bottles' sessions are untouched). This is the recovery path for
    /// a hung launch: it's the difference between a clean shutdown and Force Quitting ExeDock/killing
    /// the wine process from Activity Monitor, which leaves wineserver's helper processes orphaned.
    static func forceQuit(bottle: Bottle) throws {
        let wineBinary = try SikarugirEngine.wineBinaryPath()
        let wineServerBinary = (wineBinary as NSString).deletingLastPathComponent.appending("/wineserver")
        guard FileManager.default.isExecutableFile(atPath: wineServerBinary) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineServerBinary)
        process.arguments = ["-k"]
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.prefixPath
        process.environment = env
        try process.run()
        process.waitUntilExit()

        stateLock.lock()
        runningProcesses[bottle.id] = nil
        stateLock.unlock()
    }
}
