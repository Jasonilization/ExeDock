import Foundation
import AppKit

/// Launches Windows executables through the Sikarugir engine ExeDock reuses.
enum ExeRunner {
    static let logsDir = ("~/Library/Logs/ExeDock" as NSString).expandingTildeInPath

    /// `nil` when the launch was delegated to a wrapper app (see below) - there's no `Process`
    /// handle to hand back in that case, only a request macOS itself fulfills asynchronously.
    @discardableResult
    static func run(exePath: String, in bottle: Bottle, arguments: [String] = [], config: GameModeConfig = GameModeConfig(), engineName: String? = nil) async throws -> Process? {
        // A game living inside a *specific* Sikarugir wrapper's own bottle is launched by simply
        // opening that wrapper app itself - exactly, byte-for-byte, what double-clicking it in
        // Finder does, with no exe path or arguments handed to it at all. Two earlier, more
        // "automated" attempts at this - forcing the wrapper's own wine binary directly, then
        // handing it the target exe via macOS's "Open With" file-association mechanism - both
        // failed for real, different reasons (a hang, then still not actually launching the game),
        // despite each being based on real, verified evidence about how that wrapper works
        // internally. The one thing actually confirmed to work, repeatedly, is opening the wrapper
        // app exactly the way its own user already does by hand - so that's what this does now,
        // full stop, instead of a fourth attempt at reverse-engineering its internals: "let it go
        // from sikarugir directly... use its wrapper, everything the same," per live feedback.
        if case .sikarugirWrapper(let appPath) = bottle.kind {
            try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: NSWorkspace.OpenConfiguration())
            return nil
        }

        let wineBinary = try SikarugirEngine.wineBinaryPath(engineName: engineName ?? config.engineName)
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
        for (key, value) in try SikarugirEngine.runtimeEnvironment(engineName: engineName ?? config.engineName) { env[key] = value }
        for (key, value) in config.environment { env[key] = value }
        process.environment = env
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        return process
    }
}
