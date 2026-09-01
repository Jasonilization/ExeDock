import SwiftUI

// MARK: - Shared data resolution

/// Everything a `LibraryEntry`-based layout needs to render a tile/row, resolved once per entry
/// (Steam art/genre/description come from an async store-info fetch already used elsewhere in this
/// app; custom games already carry this synchronously). Shared by every layout below so "how do I
/// get this entry's art" isn't reimplemented six different times.
struct LibraryPresentation {
    let artPath: String?
    let genre: String?
    let description: String?
    let isCustom: Bool

    static func resolve(_ entry: LibraryEntry) async -> LibraryPresentation {
        switch entry {
        case .custom(let game):
            return LibraryPresentation(artPath: game.effectiveArtworkPath, genre: game.discovered.steamGenres.first, description: game.effectiveDescription, isCustom: true)
        case .steam(let game):
            let info = await SteamStoreInfoCache.shared.info(for: game.metadataAppID)
            return LibraryPresentation(artPath: info?.headerImagePath, genre: info?.genres.first, description: info?.shortDescription, isCustom: false)
        }
    }
}

/// A deterministic placeholder gradient for an entry with no fetched artwork yet (or none found) -
/// keyed off its id so the same game always gets the same color instead of flickering between
/// renders.
private func placeholderTile(for id: String) -> LinearGradient {
    var hasher = Hasher()
    hasher.combine(id)
    let hue = Double(abs(hasher.finalize()) % 360)
    return LinearGradient(
        colors: [Color(hue: hue / 360, saturation: 0.45, brightness: 0.55), Color(hue: ((hue + 35).truncatingRemainder(dividingBy: 360)) / 360, saturation: 0.5, brightness: 0.3)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

@ViewBuilder
private func artView(path: String?, id: String) -> some View {
    if let path, let image = LocalImageCache.image(atPath: path) {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
    } else {
        placeholderTile(for: id)
    }
}

// MARK: - Shared tile (used by Shelves, Steam-style, Carousel)

private struct LibraryEntryTile: View {
    let entry: LibraryEntry
    let width: CGFloat
    let height: CGFloat
    let onOpen: () -> Void
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    @LocalState private var presentation: LibraryPresentation?

    private var isRunning: Bool { runningTracker.runningGames[entry.id] != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                artView(path: presentation?.artPath, id: entry.id)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                if presentation?.isCustom == true {
                    Text("CUSTOM").font(.system(size: 9, weight: .bold)).padding(4).background(.purple, in: Capsule()).foregroundStyle(.white).padding(6)
                }
                if isRunning {
                    Circle().fill(.green).frame(width: 9, height: 9).padding(6)
                }
            }
            Text(entry.name).font(.callout.weight(.semibold)).lineLimit(1).frame(width: width, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .task(id: entry.id) { presentation = await LibraryPresentation.resolve(entry) }
    }
}

// MARK: - Layout A: Shelves (PS5/Xbox-style hero + horizontal rows)

struct LibraryShelvesLayout: View {
    let entries: [LibraryEntry]
    let onOpenDetail: (LibraryEntry) -> Void
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    @LocalState private var featuredPresentation: LibraryPresentation?

    private var featured: LibraryEntry? {
        runningTracker.runningGames.keys.first.flatMap { id in entries.first { $0.id == id } } ?? entries.first
    }
    private var customEntries: [LibraryEntry] { entries.filter { if case .custom = $0 { true } else { false } } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let featured {
                    ZStack(alignment: .bottomLeading) {
                        artView(path: featuredPresentation?.artPath, id: featured.id).frame(height: 300)
                        LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom).frame(height: 300)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(runningTracker.runningGames[featured.id] != nil ? "CONTINUE PLAYING" : "FEATURED")
                                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.75))
                            Text(featured.name).font(.system(size: 36, weight: .bold)).foregroundStyle(.white)
                            if let desc = featuredPresentation?.description {
                                Text(desc).font(.body).foregroundStyle(.white.opacity(0.85)).lineLimit(2).frame(maxWidth: 460, alignment: .leading)
                            }
                            Button("View Details") { onOpenDetail(featured) }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4)
                        }
                        .padding(32)
                    }
                    .task(id: featured.id) { featuredPresentation = await LibraryPresentation.resolve(featured) }
                }
                if !customEntries.isEmpty { shelf("Custom Games", customEntries) }
                shelf("Your Library", entries)
            }
        }
    }

    private func shelf(_ title: String, _ items: [LibraryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.bold()).padding(.horizontal, 32).padding(.top, 22)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items) { entry in
                        LibraryEntryTile(entry: entry, width: 190, height: 105) { onOpenDetail(entry) }
                    }
                }
                .padding(.horizontal, 32)
            }
        }
    }
}

// MARK: - Layout B: Sidebar (Music.app-style master-detail)

struct LibrarySidebarLayout: View {
    let entries: [LibraryEntry]
    let onOpenDetail: (LibraryEntry) -> Void
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    @LocalState private var selectedID: String?
    @LocalState private var presentation: LibraryPresentation?

    private var selected: LibraryEntry? {
        entries.first { $0.id == selectedID } ?? entries.first
    }

    var body: some View {
        HStack(spacing: 0) {
            List(entries, selection: Binding(get: { selectedID ?? entries.first?.id }, set: { selectedID = $0 })) { entry in
                HStack(spacing: 10) {
                    Circle().fill(placeholderTile(for: entry.id)).frame(width: 26, height: 26)
                    Text(entry.name).lineLimit(1)
                    Spacer()
                    if runningTracker.runningGames[entry.id] != nil { Circle().fill(.green).frame(width: 7, height: 7) }
                }
                .tag(entry.id)
            }
            .listStyle(.sidebar)
            .frame(width: 260)

            if let selected {
                ZStack(alignment: .bottomLeading) {
                    artView(path: presentation?.artPath, id: selected.id)
                    LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 10) {
                        if presentation?.isCustom == true { Text("CUSTOM GAME").font(.caption.bold()).foregroundStyle(.purple) }
                        Text(selected.name).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                        if let desc = presentation?.description {
                            Text(desc).font(.body).foregroundStyle(.white.opacity(0.85)).lineLimit(3).frame(maxWidth: 440, alignment: .leading)
                        }
                        Button("View Details") { onOpenDetail(selected) }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4)
                    }
                    .padding(32)
                }
                .task(id: selected.id) { presentation = await LibraryPresentation.resolve(selected) }
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Layout C: List (dense table, no artwork focus)

struct LibraryListLayout: View {
    let entries: [LibraryEntry]
    let onOpenDetail: (LibraryEntry) -> Void
    @ObservedObject private var runningTracker = RunningGameTracker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("").frame(width: 30)
                Text("TITLE").frame(maxWidth: .infinity, alignment: .leading)
                Text("STATUS").frame(width: 110, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 24).padding(.vertical, 8)
            Divider()
            ScrollView {
                ForEach(entries) { entry in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(placeholderTile(for: entry.id)).frame(width: 30, height: 30)
                        HStack(spacing: 6) {
                            Text(entry.name).font(.callout.weight(.medium))
                            if case .custom = entry { Text("CUSTOM").font(.caption2.bold()).foregroundStyle(.purple) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Group {
                            if runningTracker.runningGames[entry.id] != nil {
                                Label("Running", systemImage: "circle.fill").font(.caption.weight(.semibold)).foregroundStyle(.green)
                            } else {
                                Text("Details →").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(width: 110, alignment: .trailing)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 9)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenDetail(entry) }
                    Divider()
                }
            }
        }
    }
}

// MARK: - Layout D: Steam-style (sidebar categories + poster grid)

struct LibrarySteamStyleLayout: View {
    let entries: [LibraryEntry]
    let onOpenDetail: (LibraryEntry) -> Void
    @LocalState private var filter = "All Games"
    private let filters = ["All Games", "Custom Games"]

    private var filtered: [LibraryEntry] {
        filter == "Custom Games" ? entries.filter { if case .custom = $0 { true } else { false } } : entries
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LIBRARY").font(.caption2.weight(.bold)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 8)
                ForEach(filters, id: \.self) { f in
                    Text(f).font(.callout.weight(f == filter ? .semibold : .regular))
                        .padding(.horizontal, 14).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                        .background(f == filter ? Color.primary.opacity(0.08) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { filter = f }
                }
                Spacer()
            }
            .frame(width: 170)
            .background(Color(nsColor: .underPageBackgroundColor))

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 170), spacing: 12)], spacing: 12) {
                    ForEach(filtered) { entry in
                        LibraryEntryTile(entry: entry, width: 154, height: 210) { onOpenDetail(entry) }
                    }
                }
                .padding(18)
            }
        }
    }
}

// MARK: - Layout E: Poster Carousel (Apple TV-style, focus scales up)

struct LibraryCarouselLayout: View {
    let entries: [LibraryEntry]
    let onOpenDetail: (LibraryEntry) -> Void
    @LocalState private var focused: String?
    @LocalState private var presentation: LibraryPresentation?

    private var focusedEntry: LibraryEntry? { entries.first { $0.id == focused } ?? entries.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(entries) { entry in
                        let isFocused = entry.id == (focused ?? entries.first?.id)
                        LibraryEntryTile(entry: entry, width: isFocused ? 230 : 185, height: isFocused ? 300 : 240) {
                            if isFocused { onOpenDetail(entry) } else { focused = entry.id }
                        }
                        .scaleEffect(isFocused ? 1 : 0.96)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: focused)
                    }
                }
                .padding(.horizontal, 32).padding(.top, 20)
            }
            if let focusedEntry, let desc = presentation?.description {
                Text(desc).font(.body).foregroundStyle(.secondary).frame(maxWidth: 520, alignment: .leading).padding(.horizontal, 32)
                    .task(id: focusedEntry.id) { presentation = await LibraryPresentation.resolve(focusedEntry) }
            }
            Spacer()
        }
    }
}

// MARK: - Layout F: Launchpad (bare icon grid)

struct LibraryLaunchpadLayout: View {
    let entries: [LibraryEntry]
    let onOpenDetail: (LibraryEntry) -> Void
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    @LocalState private var presentations: [String: LibraryPresentation] = [:]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(120), spacing: 30), count: 8), spacing: 28) {
                ForEach(entries) { entry in
                    VStack(spacing: 8) {
                        ZStack(alignment: .topTrailing) {
                            artView(path: presentations[entry.id]?.artPath, id: entry.id)
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .shadow(color: .black.opacity(0.28), radius: 8, y: 5)
                            if runningTracker.runningGames[entry.id] != nil {
                                Circle().fill(.green).frame(width: 13, height: 13).overlay(Circle().stroke(.white, lineWidth: 2)).offset(x: 4, y: -4)
                            }
                        }
                        Text(entry.name).font(.caption.weight(.medium)).lineLimit(1).frame(width: 110)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenDetail(entry) }
                    .task(id: entry.id) { presentations[entry.id] = await LibraryPresentation.resolve(entry) }
                }
            }
            .padding(40)
        }
    }
}
