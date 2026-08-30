import Foundation
import AppKit

/// Launches Windows executables through the Sikarugir engine ExeDock reuses.
enum ExeRunner {
    static let logsDir = ("~/Library/Logs/ExeDock" as NSString).expandingTildeInPath

    /// `nil` when the launch was delegated to a wrapper app (see below) - there's no `Process`
    /// handle to hand back in that case, only a request macOS itself fulfills asynchronously.
    @discardableResult
    static func run(exePath: String, in bottle: Bottle, arguments: [String] = [], config: GameModeConfig = GameModeConfig(), engineName: String? = nil) async throws -> Process? {
        // A game living inside a *specific* Sikarugir wrapper's own bottle is launched by handing
        // the exe straight to that wrapper app itself - exactly like dragging the exe onto it, or
        // macOS's own "Open With," would - rather than ExeDock trying to reconstruct that engine's
        // own DirectX-backend setup itself. Real, verified mechanism: the wrapper's own Info.plist
        // declares itself able to open *any* file (`CFBundleDocumentTypes` with a wildcard `*`
        // extension) - Sikarugir/Wineskin's own standard "run this instead of my configured default
        // program" convention. This replaces an earlier, more ambitious attempt at reconstructing
        // that wrapper's real D3DMetal/DXVK activation (WINEDLLOVERRIDES, `CX_D3DMETALPATH`,
        // reverse-engineered from its own binary) - that attempt didn't just fail to help, it made
        // launches hang outright, strictly worse than before. The wrapper app already knows exactly
        // how to run anything in its own bottle correctly; ExeDock doesn't need to know how -
        // "everything from sikarugir works... just do that," per live feedback.
        if case .sikarugirWrapper(let appPath) = bottle.kind {
            let openConfig = NSWorkspace.OpenConfiguration()
            openConfig.arguments = arguments
            _ = try await NSWorkspace.shared.open(
                [URL(fileURLWithPath: exePath)],
                withApplicationAt: URL(fileURLWithPath: appPath),
                configuration: openConfig
            )
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
