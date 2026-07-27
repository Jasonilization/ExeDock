import Foundation

/// A single file or folder inside a bottle's C: drive, used by the C: Drive browser.
struct CDriveEntry: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    let isExecutable: Bool

    var id: String { path }

    static func children(of folderPath: String) -> [CDriveEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folderPath) else { return [] }
        return names
            .filter { !$0.hasPrefix(".") }
            .compactMap { name -> CDriveEntry? in
                let fullPath = (folderPath as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { return nil }
                let isExe = !isDir.boolValue && name.lowercased().hasSuffix(".exe")
                return CDriveEntry(path: fullPath, name: name, isDirectory: isDir.boolValue, isExecutable: isExe)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}
