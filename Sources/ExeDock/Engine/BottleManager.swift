import Foundation

/// Owns ExeDock's own Wine bottles (prefixes) — always separate from any Sikarugir wrapper prefix.
final class BottleManager {
    static let shared = BottleManager()

    private let bottlesRoot = (SikarugirEngine.exeDockSupportDir as NSString).appendingPathComponent("Bottles")

    let defaultBottle: Bottle
    let steamBottle: Bottle

    private init() {
        try? FileManager.default.createDirectory(atPath: bottlesRoot, withIntermediateDirectories: true)
        defaultBottle = Bottle(name: "Default", prefixPath: (bottlesRoot as NSString).appendingPathComponent("Default"), kind: .owned)
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

        let alreadyInitialized = fm.fileExists(atPath: bottle.driveCPath)
        guard !alreadyInitialized else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineBinary)
        process.arguments = ["wineboot", "--init"]
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.prefixPath
        env["WINEDEBUG"] = "-all"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
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
