import Foundation

enum SikarugirWrapperTemplateRemoteError: Error, LocalizedError {
    case requestFailed
    case noAssetsFound

    var errorDescription: String? {
        switch self {
        case .requestFailed: return "Couldn't reach Sikarugir's wrapper template releases on GitHub."
        case .noAssetsFound: return "No wrapper template was found in Sikarugir's latest Wrapper release."
        }
    }
}

/// Downloads the same public, blank wrapper-app "Template" Sikarugir Creator itself builds every
/// wrapper app from - the real, public `Sikarugir-App/Wrapper` GitHub release, the exact same
/// trusted org/pattern `SikarugirEnginesRemote` already uses for engines - to get at two things a
/// genuinely fresh install (the DMG alone, nothing else ever installed) needs and would otherwise
/// have no local source for at all:
///
/// - `Contents/Frameworks` - the ~50 shared macOS runtime libraries wine itself needs at runtime.
/// - `Contents/Configure.app` - a real, working copy of Sikarugir's own Configure app, confirmed
///   (by downloading and inspecting a real copy of this exact template) to be the same blank
///   Configure.app every built wrapper ships - kept so `ConfigureShellBuilder` can give Playdock's
///   own bottles the same reliable, Configure-driven launch path a Sikarugir Creator wrapper
///   already gets, with zero extra setup for anyone - see that file's own doc comment for why.
///
/// This is what lets first launch finish with no separate app and no manual "build a wrapper first"
/// step: previously, `SikarugirEngine.ensureFrameworksAvailable()` could only ever find this payload
/// by copying it from an *existing* Sikarugir wrapper app already on the Mac, which a brand-new user
/// simply wouldn't have - dead-ending first launch with an error asking them to go do something in a
/// completely separate app they've never heard of.
enum SikarugirWrapperTemplateRemote {
    private static let releasesURL = URL(string: "https://api.github.com/repos/Sikarugir-App/Wrapper/releases/latest")!

    /// Downloads the template tarball and extracts its `Contents/Frameworks` directory into
    /// `destinationDir` and its `Contents/Configure.app` into
    /// `SikarugirEngine.exeDockConfigureTemplatePath` (replacing anything already at either).
    /// Cleans up its own temporary files regardless of outcome; never touches anything outside
    /// ExeDock's own support directory.
    static func downloadFrameworks(into destinationDir: String, progress: @escaping (String) -> Void) async throws {
        progress("Looking for Playdock's runtime libraries…")
        let result: (data: Data, response: URLResponse)
        do {
            result = try await URLSession.shared.data(from: releasesURL)
        } catch {
            DiagnosticsLog.log("Wrapper template: releases request failed - \(error.localizedDescription)")
            throw SikarugirWrapperTemplateRemoteError.requestFailed
        }
        guard (result.response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: result.data) as? [String: Any],
              let rawAssets = json["assets"] as? [[String: Any]] else {
            throw SikarugirWrapperTemplateRemoteError.requestFailed
        }
        let candidates: [(name: String, url: URL)] = rawAssets.compactMap { asset in
            guard let name = asset["name"] as? String, name.hasSuffix(".tar.xz"),
                  let urlString = asset["browser_download_url"] as? String, let url = URL(string: urlString) else {
                return nil
            }
            return (name, url)
        }
        // Newest version first (the same natural-sort convention used everywhere else here), so a
        // template update picks up any newer renderer support automatically.
        guard let chosen = candidates.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedDescending }).first else {
            throw SikarugirWrapperTemplateRemoteError.noAssetsFound
        }

        progress("Downloading Playdock's runtime libraries…")
        let downloaded: (url: URL, response: URLResponse)
        do {
            downloaded = try await URLSession.shared.download(from: chosen.url)
        } catch {
            throw SikarugirWrapperTemplateRemoteError.requestFailed
        }
        guard (downloaded.response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SikarugirWrapperTemplateRemoteError.requestFailed
        }

        progress("Preparing Playdock's runtime libraries…")
        let fm = FileManager.default
        let supportDir = SikarugirEngine.exeDockSupportDir
        let stagingTarball = (supportDir as NSString).appendingPathComponent("WrapperTemplate.tar.xz")
        let stagingDir = (supportDir as NSString).appendingPathComponent("WrapperTemplate.staging")
        try? fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: stagingTarball)
        try? fm.removeItem(atPath: stagingDir)
        try fm.moveItem(at: downloaded.url, to: URL(fileURLWithPath: stagingTarball))
        try fm.createDirectory(atPath: stagingDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(atPath: stagingTarball)
            try? fm.removeItem(atPath: stagingDir)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xJf", stagingTarball, "-C", stagingDir]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "tar exited with status \(process.terminationStatus)"
            throw EngineError.extractionFailed(message)
        }

        // The tarball contains a single top-level "<Name>.app" - find its own Contents/Frameworks.
        guard let entries = try? fm.contentsOfDirectory(atPath: stagingDir),
              let appName = entries.first(where: { $0.hasSuffix(".app") }) else {
            throw EngineError.missingSharedLibraries
        }
        let templateAppPath = (stagingDir as NSString).appendingPathComponent(appName)
        let sourceFrameworks = templateAppPath + "/Contents/Frameworks"
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceFrameworks, isDirectory: &isDir), isDir.boolValue else {
            throw EngineError.missingSharedLibraries
        }

        try? fm.removeItem(atPath: destinationDir)
        try fm.moveItem(atPath: sourceFrameworks, toPath: destinationDir)

        // Configure.app is a nice-to-have, not required for Frameworks (the thing this function is
        // actually named for and always must succeed at) to count as done - a missing/mismatched
        // Configure.app here just means `ConfigureShellBuilder` falls back to the CLI/direct-wine
        // launch path later, exactly like it already does for a bottle with no shell at all.
        let sourceConfigure = templateAppPath + "/Contents/Configure.app"
        if fm.fileExists(atPath: sourceConfigure, isDirectory: &isDir), isDir.boolValue {
            try? fm.removeItem(atPath: SikarugirEngine.exeDockConfigureTemplatePath)
            try? fm.copyItem(atPath: sourceConfigure, toPath: SikarugirEngine.exeDockConfigureTemplatePath)
        }

        progress("Playdock's runtime libraries are ready.")
        DiagnosticsLog.log("Wrapper template: installed runtime libraries from \(chosen.name)")
    }
}
