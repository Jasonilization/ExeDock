import Foundation

/// Launches Windows executables through the Sikarugir engine ExeDock reuses.
enum ExeRunner {
    static let logsDir = ("~/Library/Logs/ExeDock" as NSString).expandingTildeInPath

    @discardableResult
    static func run(exePath: String, in bottle: Bottle, extraEnvironment: [String: String] = [:]) throws -> Process {
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
        process.arguments = [exePath]
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.prefixPath
        for (key, value) in try SikarugirEngine.runtimeEnvironment() { env[key] = value }
        for (key, value) in extraEnvironment { env[key] = value }
        process.environment = env
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        return process
    }
}
