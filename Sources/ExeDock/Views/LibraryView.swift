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
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search your apps", text: $search)
                    .textFieldStyle(.plain)
                Spacer()
                Button {
                    model.refreshBottlesAndApps()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(12)

            if model.detectedApps.isEmpty {
                emptyState
                    .transition(.opacity)
            } else {
                List {
                    ForEach(grouped, id: \.bottleName) { group in
                        Section(group.bottleName) {
                            ForEach(group.apps) { app in
                                AppRow(app: app)
                                    .fadeInOnAppear()
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.detectedApps)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No apps found yet")
                .font(.headline)
            Text("Drag an .exe above, or install something into a bottle - it'll show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
