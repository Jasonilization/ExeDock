import SwiftUI

/// A Finder-style browser for a bottle's C: drive - lets you dig into Program Files, double-click
/// an .exe to run it, or reveal any file/folder in Finder.
struct CDriveView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var controllerObserver = ControllerObserver.shared
    @AppStorage(PlaydockSkin.storageKey) private var skinRaw = PlaydockSkin.luxury.rawValue
    private var skin: PlaydockSkin { PlaydockSkin(rawValue: skinRaw) ?? .luxury }
    @LocalState private var selectedBottleID: String? = nil
    @LocalState private var pathStack: [String] = []
    /// Which row a controller's D-pad currently has highlighted - index into `entries`. Reset
    /// whenever the folder changes, since a stale index would point at an unrelated row.
    @LocalState private var focusedIndex: Int?

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
                .buttonStyle(.bordered)
                Button {
                    if !currentFolder.isEmpty { model.revealInFinder(currentFolder) }
                } label: {
                    Label("Open in Finder", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(skin.accent.opacity(0.4)).frame(height: skin.borderWidth)
            }

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
                ScrollViewReader { scrollProxy in
                    List(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        CDriveRow(entry: entry, isFocused: controllerObserver.isConnected && focusedIndex == index) {
                            handleActivate(entry)
                        } onReveal: {
                            model.revealInFinder(entry.path)
                        }
                    }
                    .listStyle(.inset)
                    .environment(\.defaultMinListRowHeight, 44)
                    .onChange(of: focusedIndex) { index in
                        guard let index, entries.indices.contains(index) else { return }
                        withAnimation { scrollProxy.scrollTo(entries[index].id, anchor: .center) }
                    }
                }
            }
            ControllerLegendBar(hints: controllerObserver.moveSelectBackHints + [controllerObserver.switchTabHint])
        }
        .onAppear {
            if selectedBottleID == nil { selectedBottleID = selectedBottle?.id }
        }
        .onChange(of: pathStack) { _ in focusedIndex = nil }
        .onChange(of: selectedBottleID) { _ in focusedIndex = nil }
        .onChange(of: controllerObserver.directionPress?.token) { _ in
            guard model.selectedSection == .cDrive, let direction = controllerObserver.directionPress?.direction else { return }
            switch direction {
            case .up: focusedIndex = max(0, (focusedIndex ?? 0) - 1)
            case .down: focusedIndex = min(entries.count - 1, (focusedIndex ?? -1) + 1)
            case .left, .right: break
            }
        }
        .onChange(of: controllerObserver.primaryPress) { _ in
            guard model.selectedSection == .cDrive, let focusedIndex, entries.indices.contains(focusedIndex) else { return }
            handleActivate(entries[focusedIndex])
        }
        // "ui looks weird for the bottle browser sometimes. make sure it has the same UI look," per
        // live feedback - this was plain, fully unstyled system chrome, the one screen in the app
        // that never picked up the active skin at all. Accent tint + font design only (not a full
        // `SkinBackground`/pinned color scheme like the game-library layouts use) - a Finder-style
        // file browser stays on native adaptive backgrounds and genuinely follows system light/dark
        // on its own, which is the correct, lower-risk way to get "the same look" here without
        // resurrecting the exact light/dark-vs-fixed-palette bug the grid's cards had.
        .skinned()
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
    let isFocused: Bool
    let onActivate: () -> Void
    let onReveal: () -> Void

    var body: some View {
        // A real, confirmed bug: this used to be one outer Button wrapping the whole row *and* a
        // second, nested Button for "reveal in Finder" inside it - a Button inside a Button inside
        // a List row with no selection binding, which macOS SwiftUI doesn't hit-test reliably.
        // Live test: clicking a folder row did nothing at all, every time, on every row. Tap
        // gesture + contentShape is the same pattern LibraryEntryTile already uses for exactly this
        // reason - a plain, working row tap with a real sibling button for the one thing that needs
        // its own separate action, not a control nested inside another control.
        HStack(spacing: 10) {
            Image(nsImage: AppIconProvider.icon(forPath: entry.path))
                .resizable()
                .frame(width: 26, height: 26)
            Text(entry.name)
                .font(.body)
            Spacer()
            if entry.isExecutable {
                Text("Run").font(.callout.weight(.medium)).foregroundStyle(Color.accentColor)
            }
            Button(action: onReveal) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .focusRing(isFocused)
    }
}
