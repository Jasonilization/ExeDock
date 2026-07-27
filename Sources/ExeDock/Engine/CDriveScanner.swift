import Foundation

/// Scans a bottle's `Program Files` folders for installed Windows programs.
enum CDriveScanner {
    private static let ignoredFolderNames: Set<String> = [
        "common files", "windows nt", "internet explorer", "windows media player",
        "installshield installation information", "windowsapps", "windows defender",
        "windows mail", "windows photo viewer", "windows portable devices",
        "windows sidebar", "microsoft.net", "reference assemblies",
    ]

    static func scan(_ bottle: Bottle) -> [DetectedApp] {
        let fm = FileManager.default
        var results: [DetectedApp] = []
        for programFilesDir in ["Program Files", "Program Files (x86)"] {
            let root = (bottle.driveCPath as NSString).appendingPathComponent(programFilesDir)
            guard let vendorFolders = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for vendor in vendorFolders {
                guard !ignoredFolderNames.contains(vendor.lowercased()) else { continue }
                let vendorPath = (root as NSString).appendingPathComponent(vendor)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: vendorPath, isDirectory: &isDir), isDir.boolValue else { continue }
                if let mainExe = mainExecutable(inFolder: vendorPath, folderName: vendor) {
                    results.append(DetectedApp(displayName: vendor, exePath: mainExe, bottle: bottle))
                }
            }
        }
        return results.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Every bottle ExeDock knows about: its own bottles plus any read-only discovered Sikarugir
    /// wrapper bottles.
    static func allKnownBottles() -> [Bottle] {
        [BottleManager.shared.defaultBottle, BottleManager.shared.steamBottle] + BottleManager.shared.discoverSikarugirWrapperBottles()
    }

    private static func mainExecutable(inFolder folder: String, folderName: String) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: folder) else { return nil }
        var candidates: [(path: String, size: Int)] = []
        for case let relativePath as String in enumerator {
            if enumerator.level > 3 {
                enumerator.skipDescendants()
                continue
            }
            guard relativePath.lowercased().hasSuffix(".exe") else { continue }
            let name = (relativePath as NSString).lastPathComponent.lowercased()
            if name.hasPrefix("unins") || name.hasPrefix("uninstall") || name.contains("setup")
                || name.contains("updater") || name.contains("crashhandler") {
                continue
            }
            let fullPath = (folder as NSString).appendingPathComponent(relativePath)
            let attrs = try? fm.attributesOfItem(atPath: fullPath)
            let size = (attrs?[.size] as? Int) ?? 0
            candidates.append((fullPath, size))
        }
        guard !candidates.isEmpty else { return nil }

        // Prefer an exe whose name matches the folder name, else fall back to the largest exe.
        let normalizedFolder = folderName.lowercased().replacingOccurrences(of: " ", with: "")
        if let matching = candidates.first(where: {
            let exeName = (($0.path as NSString).lastPathComponent as NSString)
                .deletingPathExtension.lowercased().replacingOccurrences(of: " ", with: "")
            return exeName == normalizedFolder
        }) {
            return matching.path
        }
        return candidates.max(by: { $0.size < $1.size })?.path
    }
}
