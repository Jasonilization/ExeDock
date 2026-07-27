import Foundation

enum SteamInstallError: Error, LocalizedError {
    case downloadFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let detail): return "Couldn't download Steam: \(detail)"
        case .timedOut: return "The Steam installer didn't finish in time. Check the Steam bottle and try launching it manually."
        }
    }
}

/// Downloads Valve's official Steam bootstrapper and silently installs it into ExeDock's dedicated
/// "Steam" bottle, then hands back the path to launch. Purely user-triggered - no background network
/// activity happens unless this is explicitly called.
enum SteamInstaller {
    static let steamSetupURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!

    static var steamBottle: Bottle { BottleManager.shared.steamBottle }

    static var installedSteamExePath: String {
        (steamBottle.driveCPath as NSString).appendingPathComponent("Program Files (x86)/Steam/Steam.exe")
    }

    static var isSteamInstalled: Bool {
        FileManager.default.fileExists(atPath: installedSteamExePath)
    }

    static func installAndLaunch(progress: @escaping (String) -> Void) async throws -> String {
        if isSteamInstalled {
            progress("Steam is already installed.")
            return installedSteamExePath
        }

        progress("Downloading Steam installer…")
        let (tempURL, response) = try await URLSession.shared.download(from: steamSetupURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SteamInstallError.downloadFailed("unexpected server response")
        }
        let setupPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("SteamSetup.exe")
        try? FileManager.default.removeItem(atPath: setupPath)
        try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: setupPath))

        progress("Installing Steam…")
        let bottle = steamBottle
        try await Task.detached(priority: .userInitiated) {
            let wineBinary = try SikarugirEngine.wineBinaryPath()
            try BottleManager.shared.ensureInitialized(bottle, wineBinary: wineBinary)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: wineBinary)
            process.arguments = [setupPath, "/S"]
            var env = ProcessInfo.processInfo.environment
            env["WINEPREFIX"] = bottle.prefixPath
            for (key, value) in try SikarugirEngine.runtimeEnvironment() { env[key] = value }
            process.environment = env
            try process.run()
            process.waitUntilExit()
        }.value

        // Steam's bootstrapper /S flag returns quickly while it keeps unpacking itself in the
        // background, so poll for Steam.exe rather than trusting the process exit code alone.
        progress("Finishing setup…")
        let deadline = Date().addingTimeInterval(180)
        while !isSteamInstalled {
            if Date() > deadline { throw SteamInstallError.timedOut }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }

        progress("Steam is ready.")
        return installedSteamExePath
    }
}
