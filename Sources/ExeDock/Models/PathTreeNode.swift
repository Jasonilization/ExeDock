import Foundation

/// One node in the folder-hierarchy view of Library search results - either a folder (`app == nil`,
/// `children` populated) or a leaf pointing at one `DetectedApp`. Built by `PathTree.build(from:)`.
struct PathTreeNode: Identifiable {
    let id: String
    let name: String
    let app: DetectedApp?
    let children: [PathTreeNode]?
}
