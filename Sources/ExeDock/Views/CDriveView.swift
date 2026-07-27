import SwiftUI

/// A Finder-style browser for a bottle's C: drive - lets you dig into Program Files, double-click
/// an .exe to run it, or reveal any file/folder in Finder.
struct CDriveView: View {
    @EnvironmentObject private var model: AppModel
    @LocalState private var selectedBottleID: String? = nil
    @LocalState private var pathStack: [String] = []

    private var selectedBottle: Bottle? {
        model.bottles.first { $0.id == selectedBottleID } ?? model.bottles.first
    }

    private var currentFolder: String {
        guard let bottle = selectedBottle else { return "" }
        return pathStack.reduce(bottle.driveCPath) { ($0 as NSString).appendingPathComponent($1) }
    }

    private var entries: [CDriveEntry] {
        CDriveEntry.children(of: currentFolder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Bottle", selection: bottleSelection) {
                    ForEach(model.bottles) { bottle in
                        Text(bottle.isReadOnly ? "\(bottle.name) (Sikarugir)" : bottle.name)
                            .tag(Optional(bottle.id))
                    }
                }
                .frame(maxWidth: 280)
                Spacer()
                Button {
                    model.refreshBottlesAndApps()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                Button {
                    if !currentFolder.isEmpty { model.revealInFinder(currentFolder) }
                } label: {
                    Label("Open in Finder", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
            }
            .padding(12)

            breadcrumb
            Divider()

            if model.bottles.isEmpty {
                Spacer()
                Text("No bottles yet - drag an .exe in Library to create one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else if entries.isEmpty {
                Spacer()
                Text("This folder is empty.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List(entries) { entry in
                    CDriveRow(entry: entry) {
                        handleActivate(entry)
                    } onReveal: {
                        model.revealInFinder(entry.path)
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            if selectedBottleID == nil { selectedBottleID = selectedBottle?.id }
        }
    }

    private var bottleSelection: Binding<String?> {
        Binding(
            get: { selectedBottleID ?? selectedBottle?.id },
            set: { newValue in
                selectedBottleID = newValue
                pathStack = []
            }
        )
    }

    private func handleActivate(_ entry: CDriveEntry) {
        if entry.isDirectory {
            pathStack.append(entry.name)
        } else if entry.isExecutable, let bottle = selectedBottle {
            model.run(exePath: entry.path, bottle: bottle)
        } else {
            model.revealInFinder(entry.path)
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button("C:") { pathStack = [] }
                .buttonStyle(.plain)
                .foregroundStyle(pathStack.isEmpty ? Color.primary : Color.accentColor)
            ForEach(Array(pathStack.enumerated()), id: \.offset) { index, component in
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Button(component) {
                    pathStack = Array(pathStack.prefix(index + 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(index == pathStack.count - 1 ? Color.primary : Color.accentColor)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct CDriveRow: View {
    let entry: CDriveEntry
    let onActivate: () -> Void
    let onReveal: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack {
                Image(nsImage: AppIconProvider.icon(forPath: entry.path))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(entry.name)
                Spacer()
                if entry.isExecutable {
                    Text("Run").font(.caption).foregroundStyle(.secondary)
                }
                Button(action: onReveal) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
