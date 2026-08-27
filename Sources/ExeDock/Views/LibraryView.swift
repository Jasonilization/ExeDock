import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @LocalState private var search = ""

    private var grouped: [(bottleName: String, apps: [DetectedApp])] {
        let filtered = search.isEmpty
            ? model.detectedApps
            : model.detectedApps.filter { $0.displayName.localizedCaseInsensitiveContains(search) }
        let groups = Dictionary(grouping: filtered) { $0.bottle.name }
        return groups.keys.sorted().map { name in
            (name, groups[name]!.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending })
        }
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
                List {
                    ForEach(grouped, id: \.bottleName) { group in
                        Section(group.bottleName) {
                            ForEach(group.apps) { app in
                                AppRow(app: app)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .environment(\.defaultMinListRowHeight, 52)
            }
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
