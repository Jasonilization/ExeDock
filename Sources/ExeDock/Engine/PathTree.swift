import Foundation

/// Builds the folder-hierarchy tree Library's search shows, e.g.:
/// ```
/// Steam
/// └ steamapps / common / Hollow Knight / hollow_knight.exe
/// ```
/// instead of a flat, bottle-grouped list. Root nodes are bottles; everything under them is that
/// app's `exePath` split into path components relative to the bottle's own `drive_c`.
enum PathTree {
    static func build(from apps: [DetectedApp]) -> [PathTreeNode] {
        let byBottle = Dictionary(grouping: apps) { $0.bottle.name }
        return byBottle.keys.sorted().map { bottleName in
            let root = MutableNode(name: bottleName)
            for app in byBottle[bottleName] ?? [] {
                insert(app, into: root)
            }
            return convert(root, id: bottleName)
        }
    }

    private static func insert(_ app: DetectedApp, into root: MutableNode) {
        var relativePath = app.exePath
        if relativePath.hasPrefix(app.bottle.driveCPath) {
            relativePath = String(relativePath.dropFirst(app.bottle.driveCPath.count))
        }
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return }

        var current = root
        for (index, component) in components.enumerated() {
            let child = current.children[component] ?? {
                let node = MutableNode(name: component)
                current.children[component] = node
                return node
            }()
            if index == components.count - 1 {
                child.app = app
            }
            current = child
        }
    }

    private final class MutableNode {
        let name: String
        var app: DetectedApp?
        var children: [String: MutableNode] = [:]
        init(name: String) { self.name = name }
    }

    private static func convert(_ node: MutableNode, id: String) -> PathTreeNode {
        let sortedChildren = node.children.values.sorted { lhs, rhs in
            let lhsIsFolder = lhs.app == nil
            let rhsIsFolder = rhs.app == nil
            if lhsIsFolder != rhsIsFolder { return lhsIsFolder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        let children = sortedChildren.map { convert($0, id: "\(id)/\($0.name)") }
        return PathTreeNode(id: id, name: node.name, app: node.app, children: children.isEmpty ? nil : children)
    }
}
