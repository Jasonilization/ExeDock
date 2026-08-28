import SwiftUI
import AppKit

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @LocalState private var search = ""

    private var pathTree: [PathTreeNode] {
        let filtered = search.isEmpty
            ? model.detectedApps
            : model.detectedApps.filter { $0.displayName.localizedCaseInsensitiveContains(search) }
        return PathTree.build(from: filtered)
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
                List(pathTree, children: \.children) { node in
                    rowContent(node)
                }
                .listStyle(.inset)
                .environment(\.defaultMinListRowHeight, 44)
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ node: PathTreeNode) -> some View {
        if let app = node.app {
            AppRow(app: app)
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
