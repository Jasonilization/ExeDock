import Foundation

enum EngineError: Error, LocalizedError {
    case noEngineFound
    case extractionFailed(String)
    case missingSharedLibraries

    var errorDescription: String? {
        switch self {
        case .noEngineFound:
            return "No Sikarugir Wine engine was found. Open Sikarugir Creator once and let it download an engine, then relaunch ExeDock."
        case .extractionFailed(let detail):
            return "Failed to prepare the Sikarugir engine: \(detail)"
        case .missingSharedLibraries:
            return "Couldn't find the shared runtime libraries a Sikarugir wrapper app normally provides (like libinotify). Build at least one wrapper app with Sikarugir Creator first, then relaunch ExeDock."
        }
    }
}

/// Locates and reuses the Wine engine Sikarugir Creator already downloaded, extracting a private
/// working copy into ExeDock's own support directory. Every access to Sikarugir's own files here is
/// read-only (list a directory, read a tarball) - nothing under Sikarugir's folders is ever written.
enum SikarugirEngine {
    static let sikarugirEnginesDir = ("~/Library/Application Support/Sikarugir/Engines" as NSString).expandingTildeInPath
    static let exeDockSupportDir = ("~/Library/Application Support/ExeDock" as NSString).expandingTildeInPath
    /// Where a build of ExeDock before per-engine caching always extracted to - still checked first
    /// so an existing install doesn't silently re-extract (and re-download nothing, but re-pay the
    /// tar cost) something it already has ready to go.
    static let legacyExtractedEngineDir = (exeDockSupportDir as NSString).appendingPathComponent("Engine")
    static let exeDockFrameworksDir = (exeDockSupportDir as NSString).appendingPathComponent("Frameworks")

    /// Each named engine gets its own extraction cache (`Engine-<name>`) so ExeDock can hold more
    /// than one ready at once - needed both for the engine picker (switching without re-extracting
    /// every time) and for the launch fallback ladder trying an alternate engine after a failure.
    static func extractedEngineDir(named engineName: String) -> String {
        let safeName = engineName.replacingOccurrences(of: "/", with: "-")
        return (exeDockSupportDir as NSString).appendingPathComponent("Engine-\(safeName)")
    }

    // Setup can be triggered from more than one place at once (the launch-time SetupCoordinator
    // preparing the Default bottle while the user clicks Install & Run Steam for the Steam bottle).
    // Both paths extract into the same shared Engine/Frameworks directories, so this serializes
    // them - without it, two concurrent extractions can race and leave a half-written engine behind,
    // which is exactly what produced a wineboot failure logged with the Steam bottle previously.
    private static let prepLock = NSLock()

    /// Path to the `wine` binary ExeDock should use to launch executables. Pass a specific
    /// `engineName` (one of `availableEngineNames()`) to use that engine; leave it `nil` to get
    /// whatever's already cached, or the recommended engine if nothing's cached yet.
    static func wineBinaryPath(engineName: String? = nil) throws -> String {
        prepLock.lock()
        defer { prepLock.unlock() }
        let fm = FileManager.default
        let dir = try engineDirectory(engineName: engineName, extractIfNeeded: true)
        let wine = (dir as NSString).appendingPathComponent("bin/wine")
        if fm.isExecutableFile(atPath: wine) {
            return wine
        }
        if let wrapperWine = try? findWrapperWineBinary() {
            return wrapperWine
        }
        throw EngineError.noEngineFound
    }

    /// Picks (and, if `extractIfNeeded`, extracts) the directory a given engine request resolves
    /// to. Both `wineBinaryPath` and `runtimeEnvironment` go through this so they can never disagree
    /// about which engine a launch actually used - callers must already hold `prepLock`.
    private static func engineDirectory(engineName: String?, extractIfNeeded: Bool) throws -> String {
        let fm = FileManager.default

        // No specific engine requested and something's already extracted (from this build or an
        // older one) - the cheap, common-case path.
        if engineName == nil {
            let legacyWine = (legacyExtractedEngineDir as NSString).appendingPathComponent("bin/wine")
            if fm.isExecutableFile(atPath: legacyWine) {
                return legacyExtractedEngineDir
            }
        }

        if let chosenName = engineName ?? recommendedEngineName() {
            let dir = extractedEngineDir(named: chosenName)
            let cachedWine = (dir as NSString).appendingPathComponent("bin/wine")
            if fm.isExecutableFile(atPath: cachedWine) {
                return dir
            }
            if extractIfNeeded, let tarballPath = tarballPath(for: chosenName) {
                try extractEngine(tarball: tarballPath, into: dir)
                if fm.isExecutableFile(atPath: cachedWine) {
                    return dir
                }
            }
        }

        return legacyExtractedEngineDir
    }

    /// Names of every Wine engine Sikarugir has already downloaded (for the Game Mode engine
    /// picker), newest-looking first - the same folder Sikarugir Creator itself downloads into, so
    /// this list can never drift from what Sikarugir Creator shows.
    static func availableEngineNames() -> [String] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: sikarugirEnginesDir) else { return [] }
        return items.filter { $0.hasSuffix(".tar.xz") }
            .map { $0.replacingOccurrences(of: ".tar.xz", with: "") }
            .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
    }

    /// The engine ExeDock suggests by default: prefers the in-house "Sikarugir" build over a
    /// third-party CX one, and among same-family names prefers the highest version (natural/numeric
    /// sort, so "Sikarugir-10.0" ranks above "Sikarugir-9.0" rather than sorting as text).
    static func recommendedEngineName() -> String? {
        let names = availableEngineNames() // already newest-first
        return names.first { $0.localizedCaseInsensitiveContains("sikarugir") } ?? names.first
    }

    /// True if Sikarugir Creator has already downloaded at least one engine tarball - a purely
    /// local check (no network) used by the launch-time setup flow to know whether it can just
    /// extract what's already on disk.
    static func hasDownloadedTarball() -> Bool {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: sikarugirEnginesDir) else { return false }
        return items.contains { $0.hasSuffix(".tar.xz") }
    }

    /// True if ExeDock has (or can produce) a ready-to-use engine, from any source: an already
    /// extracted copy, a tarball it will extract as a side effect of this call, or falling back to
    /// a wrapper's bundled wine.
    static func isEngineAvailable() -> Bool {
        (try? wineBinaryPath()) != nil
    }

    /// True if some engine is already extracted and ready to use - unlike `isEngineAvailable()`,
    /// this never extracts anything as a side effect. Used by setup to decide whether it's safe to
    /// silently proceed, or whether (on a genuinely fresh install with more than one engine
    /// downloaded) it should ask the user which one to use before auto-picking one for them.
    static func hasReadyCachedEngine() -> Bool {
        let fm = FileManager.default
        let legacyWine = (legacyExtractedEngineDir as NSString).appendingPathComponent("bin/wine")
        if fm.isExecutableFile(atPath: legacyWine) {
            return true
        }
        return availableEngineNames().contains { name in
            fm.isExecutableFile(atPath: (extractedEngineDir(named: name) as NSString).appendingPathComponent("bin/wine"))
        }
    }

    /// Environment variables that must be set on every wine/wineserver/wineboot process ExeDock
    /// launches. The engine tarball only contains wine's own binaries - the ~50 shared macOS
    /// libraries wine needs at runtime (libinotify, libgnutls, GStreamer, MoltenVK, …) are NOT part
    /// of it. Sikarugir Creator bundles those into every wrapper app's own Contents/Frameworks at
    /// wrapper-creation time instead, so ExeDock copies (read-only source, never edits) that same
    /// payload from an existing wrapper app once, and points DYLD_FALLBACK_LIBRARY_PATH at it.
    static func runtimeEnvironment(engineName: String? = nil) throws -> [String: String] {
        let frameworks = try ensureFrameworksAvailable()
        prepLock.lock()
        let dir = (try? engineDirectory(engineName: engineName, extractIfNeeded: false)) ?? legacyExtractedEngineDir
        prepLock.unlock()
        let engineLib = (dir as NSString).appendingPathComponent("lib")
        return ["DYLD_FALLBACK_LIBRARY_PATH": "\(frameworks):\(engineLib)"]
    }

    static let frameworksReadyMarkerPath = (exeDockFrameworksDir as NSString).appendingPathComponent(".complete")

    /// Marks ExeDock's own copied Frameworks as ready without doing the copy itself - used by
    /// `SikarugirWrapperTemplateRemote` once it has finished moving a downloaded copy into place,
    /// so `ensureFrameworksAvailable`'s own cheap marker-file check picks it up from then on exactly
    /// like a copy sourced from a local wrapper app.
    static func markFrameworksReady() {
        try? FileManager.default.createDirectory(atPath: exeDockSupportDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: frameworksReadyMarkerPath, contents: nil)
    }

    @discardableResult
    static func ensureFrameworksAvailable() throws -> String {
        prepLock.lock()
        defer { prepLock.unlock() }
        let fm = FileManager.default
        if fm.fileExists(atPath: frameworksReadyMarkerPath) {
            return exeDockFrameworksDir
        }

        guard let sourceFrameworks = try? findWrapperFrameworksDir() else {
            throw EngineError.missingSharedLibraries
        }

        try? fm.createDirectory(atPath: exeDockSupportDir, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: exeDockFrameworksDir)

        // `-c` clonefiles on APFS (instant, copy-on-write) and transparently falls back to a real
        // copy elsewhere - either way this never touches the source wrapper app.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = ["-Rc", sourceFrameworks, exeDockFrameworksDir]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, fm.fileExists(atPath: exeDockFrameworksDir) else {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "cp exited with status \(process.terminationStatus)"
            throw EngineError.extractionFailed(message)
        }

        fm.createFile(atPath: frameworksReadyMarkerPath, contents: nil)
        return exeDockFrameworksDir
    }

    private static func findWrapperFrameworksDir() throws -> String {
        let fm = FileManager.default
        let root = ("~/Applications/Sikarugir" as NSString).expandingTildeInPath
        guard let apps = try? fm.contentsOfDirectory(atPath: root) else { throw EngineError.missingSharedLibraries }
        for app in apps where app.hasSuffix(".app") {
            let frameworksPath = (root as NSString).appendingPathComponent(app) + "/Contents/Frameworks"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: frameworksPath, isDirectory: &isDir), isDir.boolValue {
                return frameworksPath
            }
        }
        throw EngineError.missingSharedLibraries
    }

    /// Path to a specific engine's tarball on disk, if Sikarugir Creator has downloaded one by that
    /// exact name (as returned by `availableEngineNames()`).
    private static func tarballPath(for engineName: String) -> String? {
        let candidate = (sikarugirEnginesDir as NSString).appendingPathComponent("\(engineName).tar.xz")
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    private static func extractEngine(tarball: String, into destinationDir: String) throws {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: exeDockSupportDir, withIntermediateDirectories: true)

        // Extract to a staging dir first so a failed extraction never leaves a broken "cached" engine.
        let stagingDir = (exeDockSupportDir as NSString).appendingPathComponent("Engine.staging")
        try? fm.removeItem(atPath: stagingDir)
        try fm.createDirectory(atPath: stagingDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xJf", tarball, "-C", stagingDir]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "tar exited with status \(process.terminationStatus)"
            try? fm.removeItem(atPath: stagingDir)
            throw EngineError.extractionFailed(message)
        }

        // Sikarugir engine tarballs contain a single top-level bundle dir (e.g. "wswine.bundle/")
        // with bin/lib/share inside. Normalize so extractedEngineDir/bin/wine always exists.
        var sourceDir = stagingDir
        if let entries = try? fm.contentsOfDirectory(atPath: stagingDir), entries.count == 1,
           let only = entries.first {
            let onlyPath = (stagingDir as NSString).appendingPathComponent(only)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: onlyPath, isDirectory: &isDir), isDir.boolValue {
                sourceDir = onlyPath
            }
        }

        try? fm.removeItem(atPath: destinationDir)
        try fm.moveItem(atPath: sourceDir, toPath: destinationDir)
        try? fm.removeItem(atPath: stagingDir)
    }

    /// A `GameModeConfig` built from whatever DirectX-backend/sync settings a Sikarugir wrapper app
    /// was actually *built* with, straight from its own Info.plist - confirmed live against a real
    /// wrapper ("Subliminal.app"), a Wineskin-style bundle whose Info.plist carries exactly these
    /// keys (`D3DMETAL`/`DXVK`/`DXMT`/`MOLTENVKCX`/`WINEESYNC`/`WINEMSYNC`, each `0` or `1`).
    /// `ExeRunner` uses this, instead of ExeDock's own per-game `GameModeConfig`, for anything
    /// launched inside that specific wrapper's bottle - "my bottle in subliminal has great
    /// settings, use that as default for custom," per live feedback. `nil` only if the wrapper's
    /// own Info.plist can't be read at all - a key it simply doesn't declare quietly keeps
    /// `GameModeConfig`'s own default rather than being guessed at.
    static func wrapperConfig(appPath: String) -> GameModeConfig? {
        guard let plist = NSDictionary(contentsOfFile: appPath + "/Contents/Info.plist") else { return nil }
        func flag(_ key: String, default defaultValue: Bool) -> Bool {
            switch plist[key] {
            case let intValue as Int: return intValue != 0
            case let stringValue as String: return (Int(stringValue) ?? (defaultValue ? 1 : 0)) != 0
            default: return defaultValue
            }
        }
        var config = GameModeConfig()
        config.d3dMetal = flag("D3DMETAL", default: config.d3dMetal)
        config.dxvk = flag("DXVK", default: config.dxvk)
        config.dxmt = flag("DXMT", default: config.dxmt)
        config.moltenVKCX = flag("MOLTENVKCX", default: config.moltenVKCX)
        config.wineESync = flag("WINEESYNC", default: config.wineESync)
        config.wineMSync = flag("WINEMSYNC", default: config.wineMSync)
        config.engineName = nil
        return config
    }

    /// The *real* environment a `GameModeConfig`'s D3DMETAL/DXVK/DXMT toggle needs in order to
    /// actually select a translation layer - not just the bare `D3DMETAL=1`-style env var
    /// `GameModeConfig.environment` used to emit on its own. Real, verified problem this fixes:
    /// plain `wine` has no built-in understanding of a bare `D3DMETAL`/`DXVK`/`DXMT` env var at
    /// all - that's a Sikarugir/CrossOver wrapper-*launcher* convention, translated internally by
    /// that launcher's own code into concrete DLL overrides (confirmed by inspecting a real
    /// wrapper's own launcher binary via `strings`: `CX_D3DMETALPATH`, `WINEDLLPATH_PREPEND`, and
    /// per-renderer folders under `Contents/Frameworks/renderer/`, plus Apple's own public Game
    /// Porting Toolkit README, which documents this exact `renderer/<name>/wine/x86_64-windows`
    /// PE-DLL layout and enabling it per-bottle through a wrapper's "Advanced Settings," not a
    /// plain env var wine reads directly). Without this, every launch silently fell back to wine's
    /// own conservative built-in wined3d-over-Vulkan renderer regardless of which toggle was
    /// selected - confirmed as the real cause of a real Unreal Engine 5 title's launch failure,
    /// which loaded fully (assets, audio, Steam SDK) and only then failed to create a D3D11 device
    /// because that renderer refused an unrecognized GPU's feature level. ExeDock's own copied
    /// Frameworks (see `ensureFrameworksAvailable`) already carry this exact `renderer/` folder
    /// (copied wholesale from whatever wrapper app supplied them), so no extra download is needed
    /// beyond what launching already requires.
    static func rendererEnvironment(frameworksDir: String, config: GameModeConfig) -> [String: String] {
        var environment: [String: String] = [
            "MOLTENVKCX": config.moltenVKCX ? "1" : "0",
            "WINEESYNC": config.wineESync ? "1" : "0",
            "WINEMSYNC": config.wineMSync ? "1" : "0",
        ]
        let rendererName = config.d3dMetal ? "d3dmetal" : (config.dxvk ? "dxvk" : (config.dxmt ? "dxmt" : nil))
        guard let rendererName else { return environment }

        let rendererDir = (frameworksDir as NSString).appendingPathComponent("renderer/\(rendererName)")
        let peDLLDir = (rendererDir as NSString).appendingPathComponent("wine/x86_64-windows")
        guard FileManager.default.fileExists(atPath: peDLLDir) else { return environment }

        environment["WINEDLLOVERRIDES"] = "d3d11,d3d10core,d3d12,dxgi,nvapi,nvapi64,nvngx=n,b"
        environment["WINEDLLPATH_PREPEND"] = peDLLDir
        if rendererName == "d3dmetal" {
            environment["CX_D3DMETALPATH"] = rendererDir
        }
        return environment
    }

    /// Last-resort fallback: read (never write) the wine binary bundled inside an already-installed
    /// Sikarugir wrapper app, if no engine tarball is cached yet.
    private static func findWrapperWineBinary() throws -> String {
        let fm = FileManager.default
        let root = ("~/Applications/Sikarugir" as NSString).expandingTildeInPath
        guard let apps = try? fm.contentsOfDirectory(atPath: root) else { throw EngineError.noEngineFound }
        for app in apps where app.hasSuffix(".app") {
            let winePath = (root as NSString).appendingPathComponent(app) + "/Contents/SharedSupport/wine/bin/wine"
            if fm.isExecutableFile(atPath: winePath) {
                return winePath
            }
        }
        throw EngineError.noEngineFound
    }
}
