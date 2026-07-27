import Foundation

/// A Wine prefix ExeDock can run executables inside of.
struct Bottle: Identifiable, Hashable {
    enum Kind: Hashable {
        /// A bottle ExeDock owns and created itself.
        case owned
        /// A bottle discovered inside an existing Sikarugir wrapper app. Read-only.
        case sikarugirWrapper(appPath: String)
    }

    var id: String { prefixPath }
    let name: String
    let prefixPath: String
    let kind: Kind

    var driveCPath: String {
        (prefixPath as NSString).appendingPathComponent("drive_c")
    }

    var isReadOnly: Bool {
        if case .sikarugirWrapper = kind { return true }
        return false
    }
}
