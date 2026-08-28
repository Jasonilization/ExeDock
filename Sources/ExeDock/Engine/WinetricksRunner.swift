import Foundation

enum WinetricksError: Error, LocalizedError {
    case notFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Couldn't find winetricks - build at least one wrapper app with Sikarugir Creator first (it bundles a copy), then try again."
        case .failed(let detail):
            return "Installing runtime components failed: \(detail)"
        }
    }
}

/// Runs `winetricks` verbs (DirectX/C++ runtime/fonts installers) against one of Playdock's own
/// bottles. Confirmed by inspecting an existing, working Sikarugir wrapper app
/// (`Contents/SharedSupport/winetricks`) that this is exactly the mechanism Sikarugir itself uses to
/// get games' runtime dependencies working - a real, well-known, widely-used open-source tool
/// (not something exotic), read-only-referenced from a wrapper app the same way
/// `SikarugirEngine.ensureFrameworksAvailable()` already reads that app's `Frameworks` folder, and
/// copied once into Playdock's own support directory so it works even if that wrapper is later
/// removed.
///
/// Note: Playdock's own bottles already have the core VC++ runtime DLLs (msvcp140.dll,
/// vcruntime140.dll, etc. - confirmed present via a direct check, matching what winetricks' own
/// `vcrun2026` verb installs) - they evidently ship with the Sikarugir engine itself. What Playdock
/// didn't have was any general way to pull in whatever *else* a specific game needs (DirectX
/// components, fonts, .NET) - this is that.
enum WinetricksRunner {
    private static let scriptPath = (SikarugirEngine.exeDockSupportDir as NSString).appendingPathComponent("winetricks")

    /// A short, broadly-useful default set: the C++ runtime (already present for most games, but
    /// harmless/fast to confirm), classic DirectX 9 D3DX (a common older-game dependency), and the
    /// core Microsoft fonts many games expect to find installed.
    static let defaultVerbs = ["vcrun2026", "d3dx9", "corefonts"]

    static func runDefaultVerbs(in bottle: Bottle, progress: @escaping (String) -> Void) async throws {
        try await run(verbs: defaultVerbs, in: bottle, progress: progress)
    }

    static func run(verbs: [String], in bottle: Bottle, progress: @escaping (String) -> Void) async throws {
        guard !bottle.isReadOnly else {
            throw WinetricksError.failed("Refusing to modify a Sikarugir-owned bottle.")
        }
        progress("Locating winetricks…")
        let script = try ensureScriptAvailable()

        let wineBinary = try SikarugirEngine.wineBinaryPath()
        try? FileManager.default.createDirectory(atPath: ExeRunner.logsDir, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let logPath = (ExeRunner.logsDir as NSString).appendingPathComponent("winetricks-\(timestamp).log")
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let logHandle = FileHandle(forWritingAtPath: logPath)

        progress("Installing \(verbs.joined(separator: ", "))… this can take a few minutes the first time.")

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script, "-q"] + verbs
            var env = ProcessInfo.processInfo.environment
            env["WINE"] = wineBinary
            env["WINEPREFIX"] = bottle.prefixPath
            env["WINEDEBUG"] = "-all"
            for (key, value) in try SikarugirEngine.runtimeEnvironment() { env[key] = value }
            process.environment = env
            process.standardOutput = logHandle
            process.standardError = logHandle
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw WinetricksError.failed("winetricks exited with status \(process.terminationStatus). Details were saved to \(logPath).")
            }
        }.value

        progress("Done.")
        DiagnosticsLog.log("winetricks: installed \(verbs.joined(separator: ", ")) into \(bottle.name)")
    }

    /// Copies winetricks (read-only source, never edits) from any discovered Sikarugir wrapper app
    /// into Playdock's own support directory, once - same pattern as
    /// `SikarugirEngine.ensureFrameworksAvailable()`.
    private static func ensureScriptAvailable() throws -> String {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: scriptPath) {
            return scriptPath
        }
        guard let source = findWrapperWinetricks() else {
            throw WinetricksError.notFound
        }
        try? fm.createDirectory(atPath: SikarugirEngine.exeDockSupportDir, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: scriptPath)
        try fm.copyItem(atPath: source, toPath: scriptPath)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        return scriptPath
    }

    private static func findWrapperWinetricks() -> String? {
        let fm = FileManager.default
        let root = ("~/Applications/Sikarugir" as NSString).expandingTildeInPath
        guard let apps = try? fm.contentsOfDirectory(atPath: root) else { return nil }
        for app in apps where app.hasSuffix(".app") {
            let candidate = (root as NSString).appendingPathComponent(app) + "/Contents/SharedSupport/winetricks"
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
