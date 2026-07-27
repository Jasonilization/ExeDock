import Foundation

/// A Windows executable ExeDock found while scanning a bottle's C: drive.
struct DetectedApp: Identifiable, Hashable {
    var id: String { exePath }
    let displayName: String
    let exePath: String
    let bottle: Bottle
}
