import Foundation
import AppKit

/// Launches a game inside a real Sikarugir wrapper bottle by driving that wrapper's own Configure
/// app - set its "Windows app" path to the target exe, then trigger its own "Test Run" action -
/// instead of trying to replicate wine's own invocation ourselves. Confirmed live, repeatedly: the
/// raw wrapper CLI (`Contents/MacOS/Sikarugir run <exe>`) fails with a WineAppInitializationError
/// that never reproduces outside it even against a known-good prefix, and a direct
/// `wine start /unix <exe>` invocation gets some titles running but not others (a real D3D12/vkd3d
/// limitation against this Mac's Vulkan/MoltenVK stack, confirmed independent of invocation style).
/// Configure's own Test Run, against the exact same engine/bottle/title, has launched every game
/// tried this way - "the test run works perfectly well," per live, repeated feedback.
///
/// Drives Configure through the Accessibility APIs (found via inspection - a real AXTextField for
/// the path, a real AXButton named "Test Run" - not a blind keystroke sent to whatever's frontmost).
/// This is the same class of interaction a person clicking through Configure by hand would trigger;
/// whatever Configure does differently internally that makes it reliable isn't fully known, but the
/// mechanism to reach it is straightforward once you know where the path field and button live.
enum SikarugirConfigureLauncher {
    enum LauncherError: Error, LocalizedError {
        case noConfigureApp
        case pathNotInBottle
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .noConfigureApp: return "This wrapper doesn't have its own Configure app."
            case .pathNotInBottle: return "That exe isn't inside this wrapper's own bottle."
            case .scriptFailed(let detail): return "Couldn't drive Configure: \(detail)"
            }
        }
    }

    /// Converts an absolute macOS path inside a bottle's drive_c into the Windows-style path
    /// Configure's own "Windows app" field expects (e.g. `C:\Program Files (x86)\...\Game.exe`).
    static func windowsPath(forExePath exePath: String, driveCPath: String) -> String? {
        guard exePath.hasPrefix(driveCPath) else { return nil }
        let relative = String(exePath.dropFirst(driveCPath.count))
        return "C:" + relative.replacingOccurrences(of: "/", with: "\\")
    }

    /// Sets the wrapper's own Configure app to the given exe's path and triggers its Test Run
    /// action. Doesn't return a handle to whatever process starts - the actual launch is entirely
    /// Configure's own doing from here, matching the existing convention (see `ExeRunner`) for a
    /// launch this code doesn't directly own a `Process` for.
    static func launch(exePath: String, wrapperAppPath: String, driveCPath: String) async throws {
        guard let winPath = windowsPath(forExePath: exePath, driveCPath: driveCPath) else {
            throw LauncherError.pathNotInBottle
        }
        let configurePath = wrapperAppPath + "/Contents/Configure.app"
        guard FileManager.default.fileExists(atPath: configurePath) else {
            throw LauncherError.noConfigureApp
        }

        try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: configurePath), configuration: NSWorkspace.OpenConfiguration())

        // Configure's own process name in the Accessibility tree - confirmed live via System
        // Events, matches the bundle name every real Sikarugir/Wineskin wrapper ships this as.
        let processName = ((configurePath as NSString).lastPathComponent as NSString).deletingPathExtension
        let escapedPath = winPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "System Events"
            tell process "\(processName)"
                set frontmost to true
                repeat 25 times
                    if (count windows) > 0 then exit repeat
                    delay 0.2
                end repeat
                if (count windows) = 0 then error "Configure's window never appeared."
                tell window 1
                    tell tab group 1
                        set value of text field 1 to "\(escapedPath)"
                    end tell
                end tell
                delay 0.3
                click button "Test Run" of window 1
            end tell
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LauncherError.scriptFailed(message?.isEmpty == false ? message! : "osascript exited with status \(process.terminationStatus)")
        }
    }
}
