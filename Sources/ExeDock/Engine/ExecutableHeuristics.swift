import Foundation

/// Shared heuristics for recognizing "the real" game/program executable in a folder full of them -
/// vs. installer/uninstaller/updater/anti-cheat noise that often sits right next to it. Used
/// everywhere Playdock walks a folder looking for what to actually launch: Steam's own icon-exe
/// lookup (`SteamLibrary`), the generic Program Files scanner (`CDriveScanner`), and manually
/// imported custom games (`CustomGameFolderScanner`) - previously each kept their own
/// slightly-different copy of this same ignore list.
enum ExecutableHeuristics {
    /// Substrings that mark an exe as *not* the real game/program.
    static let ignoredExeHints = [
        "unins", "uninstall", "setup", "updater", "crashhandler", "crashreport",
        "vconsole", "easyanticheat", "battleye", "vcredist", "dxsetup", "dotnet",
    ]

    static func isLikelyIgnorable(exeName: String) -> Bool {
        let name = exeName.lowercased()
        return ignoredExeHints.contains { name.contains($0) }
    }

    /// Every plausible candidate `.exe` under `folder`, largest-first - the "biggest exe is probably
    /// the real one" heuristic every caller here already relied on, just exposed as a full list
    /// instead of picking just one, so a caller with a genuine ambiguity (an imported folder with
    /// more than one real-looking exe) can ask the user instead of silently guessing.
    static func candidateExecutables(inFolder folder: String, maxDepth: Int = 5) -> [(path: String, size: Int)] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: folder) else { return [] }
        var candidates: [(path: String, size: Int)] = []
        for case let relativePath as String in enumerator {
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            guard relativePath.lowercased().hasSuffix(".exe") else { continue }
            let name = (relativePath as NSString).lastPathComponent
            guard !isLikelyIgnorable(exeName: name) else { continue }
            let fullPath = (folder as NSString).appendingPathComponent(relativePath)
            let attrs = try? fm.attributesOfItem(atPath: fullPath)
            let size = (attrs?[.size] as? Int) ?? 0
            candidates.append((fullPath, size))
        }
        return candidates.sorted { $0.size > $1.size }
    }

    /// The single best guess among `candidateExecutables` - largest file, optionally preferring one
    /// whose name matches `preferredName` (e.g. the containing folder's own name) when there is one.
    static func bestGuessExecutable(inFolder folder: String, preferredName: String? = nil, maxDepth: Int = 5) -> String? {
        let candidates = candidateExecutables(inFolder: folder, maxDepth: maxDepth)
        guard !candidates.isEmpty else { return nil }
        if let preferredName {
            let normalizedPreferred = preferredName.lowercased().replacingOccurrences(of: " ", with: "")
            if let matching = candidates.first(where: {
                let exeName = (($0.path as NSString).lastPathComponent as NSString)
                    .deletingPathExtension.lowercased().replacingOccurrences(of: " ", with: "")
                return exeName == normalizedPreferred
            }) {
                return matching.path
            }
        }
        return candidates.first?.path
    }
}
