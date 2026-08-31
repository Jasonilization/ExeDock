import Foundation

/// Owns ExeDock's own Wine bottles (prefixes) — always separate from any Sikarugir wrapper prefix.
final class BottleManager {
    static let shared = BottleManager()

    private let bottlesRoot = (SikarugirEngine.exeDockSupportDir as NSString).appendingPathComponent("Bottles")

    let defaultBottle: Bottle
    let steamBottle: Bottle

    private init() {
        try? FileManager.default.createDirectory(atPath: bottlesRoot, withIntermediateDirectories: true)
        // Named "Playdock", not "Default" - this is the one shared bottle every custom game (and
        // any dropped .exe with nowhere else to go) actually lands in, so it should read as
        // Playdock's own bottle wherever its name surfaces (the C: drive browser, launch overlay,
        // "Opened <bottle.name>…" status line) rather than a generic internal label. The on-disk
        // folder name stays "Default" on purpose - renaming *that* would orphan every existing
        // user's already-imported custom games on update, for a rename nobody asked for.
        defaultBottle = Bottle(name: "Playdock", prefixPath: (bottlesRoot as NSString).appendingPathComponent("Default"), kind: .owned)
        steamBottle = Bottle(name: "Steam", prefixPath: (bottlesRoot as NSString).appendingPathComponent("Steam"), kind: .owned)
    }

    /// Ensures the bottle's prefix directory exists and has been initialized (`wine wineboot --init`).
    /// Refuses to run against a read-only (Sikarugir wrapper) bottle.
    func ensureInitialized(_ bottle: Bottle, wineBinary: String) throws {
        guard !bottle.isReadOnly else {
            throw EngineError.extractionFailed("Refusing to initialize a Sikarugir-owned bottle.")
        }
        let fm = FileManager.default
        try fm.createDirectory(atPath: bottle.prefixPath, withIntermediateDirectories: true)

        // system.reg only appears once wineboot has actually finished - drive_c/dosdevices alone can
        // exist from a wine invocation that started but crashed (e.g. missing shared libraries)
        // before finishing, so checking for it alone would wrongly call a broken prefix "ready".
        let systemRegPath = (bottle.prefixPath as NSString).appendingPathComponent("system.reg")
        guard !fm.fileExists(atPath: systemRegPath) else { return }

        try? fm.createDirectory(atPath: ExeRunner.logsDir, withIntermediateDirectories: true)
        let logPath = (ExeRunner.logsDir as NSString).appendingPathComponent("wineboot-\(bottle.name)-\(Int(Date().timeIntervalSince1970)).log")
        fm.createFile(atPath: logPath, contents: nil)
        let logHandle = FileHandle(forWritingAtPath: logPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineBinary)
        process.arguments = ["wineboot", "--init"]
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.prefixPath
        env["WINEDEBUG"] = "-all"
        for (key, value) in try SikarugirEngine.runtimeEnvironment() { env[key] = value }
        process.environment = env
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        process.waitUntilExit()

        // wineboot can keep finishing registry setup via background helper processes (rundll32,
        // services.exe, …) even after the process we launched exits, so give it a grace period
        // rather than assuming completion the instant it returns.
        let deadline = Date().addingTimeInterval(45)
        while !fm.fileExists(atPath: systemRegPath), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
        }

        guard fm.fileExists(atPath: systemRegPath) else {
            throw EngineError.extractionFailed("Wine's setup didn't finish in time. Details were saved to \(logPath).")
        }

        // Best-effort and fire-and-forget on purpose: a freshly-created bottle should quietly pick
        // up the common runtime components (DirectX, C++, fonts) real games often need, with no
        // button and no extra step for anyone to think about - but this must never block or fail
        // bottle setup itself. If it doesn't work (offline, etc.) the bottle is still perfectly
        // usable; it just won't have these extras until the next successful attempt.
        Task.detached(priority: .utility) {
            do {
                try await WinetricksRunner.runDefaultVerbs(in: bottle) { _ in }
            } catch {
                DiagnosticsLog.log("Runtime components for \(bottle.name): \(error.localizedDescription)")
            }
        }
    }

    /// Discovers Sikarugir wrapper apps on disk (read-only) so their bottles can be browsed and their
    /// programs launched through ExeDock's own engine copy. Nothing here writes into a wrapper app.
    func discoverSikarugirWrapperBottles() -> [Bottle] {
        let fm = FileManager.default
        let root = ("~/Applications/Sikarugir" as NSString).expandingTildeInPath
        guard let apps = try? fm.contentsOfDirectory(atPath: root) else { return [] }

        return apps.filter { $0.hasSuffix(".app") }.compactMap { appName -> Bottle? in
            let appPath = (root as NSString).appendingPathComponent(appName)
            let candidatePrefixes = [
                appPath + "/Contents/SharedSupport/prefix",
                appPath + "/Contents"
            ]
            for prefix in candidatePrefixes {
                let driveC = (prefix as NSString).appendingPathComponent("drive_c")
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: driveC, isDirectory: &isDir), isDir.boolValue {
                    let name = (appName as NSString).deletingPathExtension
                    return Bottle(name: name, prefixPath: prefix, kind: .sikarugirWrapper(appPath: appPath))
                }
            }
            return nil
        }
    }
}
