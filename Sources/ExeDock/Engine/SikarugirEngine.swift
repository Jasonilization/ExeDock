import Foundation

enum EngineError: Error, LocalizedError {
    case noEngineFound
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noEngineFound:
            return "No Sikarugir Wine engine was found. Open Sikarugir Creator once and let it download an engine, then relaunch ExeDock."
        case .extractionFailed(let detail):
            return "Failed to prepare the Sikarugir engine: \(detail)"
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

    /// Path to the `wine` binary ExeDock should use to launch executables.
    static func wineBinaryPath() throws -> String {
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
