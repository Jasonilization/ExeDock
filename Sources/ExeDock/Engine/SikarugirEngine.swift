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
    static let extractedEngineDir = (exeDockSupportDir as NSString).appendingPathComponent("Engine")
    static let exeDockFrameworksDir = (exeDockSupportDir as NSString).appendingPathComponent("Frameworks")

    // Setup can be triggered from more than one place at once (the launch-time SetupCoordinator
    // preparing the Default bottle while the user clicks Install & Run Steam for the Steam bottle).
    // Both paths extract into the same shared Engine/Frameworks directories, so this serializes
    // them - without it, two concurrent extractions can race and leave a half-written engine behind,
    // which is exactly what produced a wineboot failure logged with the Steam bottle previously.
    private static let prepLock = NSLock()

    /// Path to the `wine` binary ExeDock should use to launch executables.
    static func wineBinaryPath() throws -> String {
        prepLock.lock()
        defer { prepLock.unlock() }
        let fm = FileManager.default

        let cachedWine = (extractedEngineDir as NSString).appendingPathComponent("bin/wine")
        if fm.isExecutableFile(atPath: cachedWine) {
            return cachedWine
        }

        if let tarball = try? findSikarugirEngineTarball() {
            try extractEngine(tarball: tarball)
            if fm.isExecutableFile(atPath: cachedWine) {
                return cachedWine
            }
        }

        if let wrapperWine = try? findWrapperWineBinary() {
            return wrapperWine
        }

        throw EngineError.noEngineFound
    }

    /// Names of every Wine engine Sikarugir has already downloaded (for the Game Mode engine picker).
    static func availableEngineNames() -> [String] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: sikarugirEnginesDir) else { return [] }
        return items.filter { $0.hasSuffix(".tar.xz") }
            .map { $0.replacingOccurrences(of: ".tar.xz", with: "") }
            .sorted()
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

    /// Environment variables that must be set on every wine/wineserver/wineboot process ExeDock
    /// launches. The engine tarball only contains wine's own binaries - the ~50 shared macOS
    /// libraries wine needs at runtime (libinotify, libgnutls, GStreamer, MoltenVK, …) are NOT part
    /// of it. Sikarugir Creator bundles those into every wrapper app's own Contents/Frameworks at
    /// wrapper-creation time instead, so ExeDock copies (read-only source, never edits) that same
    /// payload from an existing wrapper app once, and points DYLD_FALLBACK_LIBRARY_PATH at it.
    static func runtimeEnvironment() throws -> [String: String] {
        let frameworks = try ensureFrameworksAvailable()
        let engineLib = (extractedEngineDir as NSString).appendingPathComponent("lib")
        return ["DYLD_FALLBACK_LIBRARY_PATH": "\(frameworks):\(engineLib)"]
    }

    @discardableResult
    private static func ensureFrameworksAvailable() throws -> String {
        prepLock.lock()
        defer { prepLock.unlock() }
        let fm = FileManager.default
        let marker = (exeDockFrameworksDir as NSString).appendingPathComponent(".complete")
        if fm.fileExists(atPath: marker) {
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

        fm.createFile(atPath: marker, contents: nil)
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

    private static func findSikarugirEngineTarball() throws -> String {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: sikarugirEnginesDir) else {
            throw EngineError.noEngineFound
        }
        let tarballs = items.filter { $0.hasSuffix(".tar.xz") }
        // Prefer the in-house "Sikarugir" engine over a third-party CX build.
        let preferred = tarballs.first { $0.localizedCaseInsensitiveContains("sikarugir") } ?? tarballs.first
        guard let chosen = preferred else { throw EngineError.noEngineFound }
        return (sikarugirEnginesDir as NSString).appendingPathComponent(chosen)
    }

    private static func extractEngine(tarball: String) throws {
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

        try? fm.removeItem(atPath: extractedEngineDir)
        try fm.moveItem(atPath: sourceDir, toPath: extractedEngineDir)
        try? fm.removeItem(atPath: stagingDir)
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
