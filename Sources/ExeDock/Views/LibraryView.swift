import SwiftUI
import AppKit

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var controllerObserver = ControllerObserver.shared
    @LocalState private var search = ""
    /// Which row a controller's D-pad currently has highlighted, by node id. Kept as an id rather
    /// than an index since the tree's flattened order only matters at the moment of navigating it.
    @LocalState private var focusedNodeID: String?

    private var pathTree: [PathTreeNode] {
        let filtered = search.isEmpty
            ? model.detectedApps
            : model.detectedApps.filter { $0.displayName.localizedCaseInsensitiveContains(search) }
        return PathTree.build(from: filtered)
    }

    /// Depth-first, pre-order flattening of the whole tree - a simplifying assumption that every
    /// disclosure group is expanded, since `List(_:children:)` doesn't expose its own live
    /// collapse state to read back. Good enough for what's normally a shallow hierarchy (bottle ->
    /// steamapps -> common -> game folder -> exe).
    private var flattenedNodes: [PathTreeNode] {
        func flatten(_ nodes: [PathTreeNode]) -> [PathTreeNode] {
            nodes.flatMap { [$0] + flatten($0.children ?? []) }
        }
        return flatten(pathTree)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                TextField("Search your apps", text: $search)
                    .textFieldStyle(.plain)
                    .font(.title3)
                Spacer()
                Button {
                    model.refreshBottlesAndApps()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)

            if model.detectedApps.isEmpty {
                emptyState
            } else {
                // A real folder hierarchy (bottle -> steamapps -> common -> Hollow Knight ->
                // hollow_knight.exe) instead of a flat list - built by PathTree, rendered with
                // SwiftUI's own List(_:children:) disclosure support, no custom plumbing needed.
                ScrollViewReader { scrollProxy in
                    List(pathTree, children: \.children) { node in
                        rowContent(node)
                    }
                    .listStyle(.inset)
                    .environment(\.defaultMinListRowHeight, 44)
                    .onChange(of: focusedNodeID) { id in
                        guard let id else { return }
                        withAnimation { scrollProxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .onChange(of: search) { _ in focusedNodeID = nil }
        .onChange(of: controllerObserver.directionPress?.token) { _ in
            guard model.selectedSection == .library, let direction = controllerObserver.directionPress?.direction else { return }
            moveFocus(direction)
        }
        .onChange(of: controllerObserver.primaryPress) { _ in
            guard model.selectedSection == .library,
                  let node = flattenedNodes.first(where: { $0.id == focusedNodeID }),
                  let app = node.app else { return }
            model.run(exePath: app.exePath, bottle: app.bottle)
        }
    }

    private func moveFocus(_ direction: ControllerDirection) {
        let nodes = flattenedNodes
        guard !nodes.isEmpty else { return }
        guard direction == .up || direction == .down else { return }
        guard let currentID = focusedNodeID, let currentIndex = nodes.firstIndex(where: { $0.id == currentID }) else {
            focusedNodeID = nodes.first?.id
            return
        }
        let nextIndex = direction == .up ? currentIndex - 1 : currentIndex + 1
        focusedNodeID = nodes[safe: nextIndex]?.id ?? currentID
    }

    @ViewBuilder
    private func rowContent(_ node: PathTreeNode) -> some View {
        if let app = node.app {
            AppRow(app: app, isFocused: controllerObserver.isConnected && focusedNodeID == node.id)
                .contextMenu {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(app.exePath, forType: .string)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }
                    Button {
                        model.revealInFinder(app.bottle.driveCPath)
                    } label: {
                        Label("Open Bottle", systemImage: "internaldrive")
                    }
                }
        } else {
            Label(node.name, systemImage: "folder")
                .font(.body)
                .foregroundStyle(.secondary)
                .focusRing(controllerObserver.isConnected && focusedNodeID == node.id)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No apps found yet")
                .font(.title2)
                .bold()
            Text("Drag an .exe above, or install something into a bottle - it'll show up here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
