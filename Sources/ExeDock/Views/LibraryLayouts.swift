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

    /// What shape of tile is asking - every portrait/square tile used to force-crop the landscape
    /// store banner because portrait/square art was never looked for at all. Each call site says
    /// its own real shape so this can hand back whatever Steam actually has cached that fits it,
    /// instead of one art path everyone force-fits.
    enum Shape {
        case landscape, portrait, square
    }

    static func resolve(_ entry: LibraryEntry, shape: Shape = .landscape) async -> LibraryPresentation {
        switch entry {
        case .custom(let game):
            return LibraryPresentation(artPath: game.effectiveArtworkPath, genre: game.discovered.steamGenres.first, description: game.effectiveDescription, isCustom: true)
        case .steam(let game):
            let info = await SteamStoreInfoCache.shared.info(for: game.metadataAppID)
            return LibraryPresentation(artPath: preferredArtPath(appID: game.metadataAppID, shape: shape, bannerPath: info?.headerImagePath), genre: info?.genres.first, description: info?.shortDescription, isCustom: false)
        }
    }

    /// Applies the user's `PlaydockArtSource` choice for a Steam game - Steam's own real, natively-
    /// shaped art (portrait box art, or a real square icon) when set to `.boxArt` and actually
    /// cached locally, falling back to the landscape banner otherwise (a game Steam hasn't cached
    /// that shape for yet, the setting is `.banner`, or this call site wants landscape anyway, which
    /// the banner already natively is).
    private static func preferredArtPath(appID: String, shape: Shape, bannerPath: String?) -> String? {
        let source = PlaydockArtSource(rawValue: UserDefaults.standard.string(forKey: PlaydockArtSource.storageKey) ?? "") ?? .banner
        guard source == .boxArt else { return bannerPath }
        switch shape {
        case .landscape:
            return bannerPath
        case .portrait:
            return SteamLibraryCache.portraitArtPath(appID: appID) ?? bannerPath
        case .square:
            return SteamLibraryCache.iconPath(appID: appID) ?? bannerPath
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

/// A small, square real-art icon for a row-based layout (Sidebar's list, List's rows) - resolves
/// its own art independently of whatever else on screen is showing that entry, so a row shows the
/// actual game icon the instant its own fetch completes rather than staying a flat placeholder
/// color forever. Square real art, falling back to the same placeholder gradient only for the
/// entries that genuinely have no art at all.
private struct SmallArtIcon: View {
    let entry: LibraryEntry
    var size: CGFloat = 30
    var cornerRadius: CGFloat = 7
    @LocalState private var presentation: LibraryPresentation?

    var body: some View {
        artView(path: presentation?.artPath, id: entry.id)
            .frame(width: size, height: size)
            .skinArtTreatment()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: entry.id) { presentation = await LibraryPresentation.resolve(entry, shape: .square) }
    }
}

// MARK: - Shared tile (used by Shelves, Steam-style, Carousel)

private struct LibraryEntryTile: View {
    let entry: LibraryEntry
    let width: CGFloat
    let height: CGFloat
    /// The real shape this tile actually is - Shelves' shelf rows are landscape (190x105), Steam-
    /// style/Carousel tiles are portrait (154x210, 185x300) - `LibraryPresentation.resolve` uses
    /// this to hand back whichever real Steam art actually fits instead of one shape everyone
    /// force-crops.
    var artShape: LibraryPresentation.Shape = .landscape
    let onOpen: () -> Void
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    @LocalState private var presentation: LibraryPresentation?
    @LocalState private var isHovering = false

    private var isRunning: Bool { runningTracker.runningGames[entry.id] != nil }
    private var gameAccent: Color? { presentation?.artPath.flatMap { GameArtColor.dominantColor(forImagePath: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                artView(path: presentation?.artPath, id: entry.id)
                    .frame(width: width, height: height)
                    .skinArtTreatment()
                    .tileSurface(isHovering: isHovering, accentOverride: gameAccent)
                    .onHover { isHovering = $0 }
                if presentation?.isCustom == true {
                    Text("CUSTOM").font(.system(size: 9, weight: .bold)).padding(4).background(.purple, in: Capsule()).foregroundStyle(.white).padding(6)
                }
                if isRunning {
                    Circle().fill(.green).frame(width: 9, height: 9).padding(6)
                }
            }
            SkinTitleText(text: entry.name, size: 15).frame(width: width, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .task(id: entry.id) { presentation = await LibraryPresentation.resolve(entry, shape: artShape) }
    }
}

// MARK: - Layout A: Shelves (PS5/Xbox-style hero + horizontal rows)

struct LibraryShelvesLayout: View {
    let entries: [LibraryEntry]
    let onOpenDetail: (LibraryEntry) -> Void
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    @LocalState private var featuredPresentation: LibraryPresentation?
    /// Set the instant someone uses the prev/next arrows - once they have, that choice sticks
    /// (browsing away and back doesn't silently snap back to whatever's running/first). The hero
    /// used to be permanently `entries.first` with no way to change it at all.
    @LocalState private var manualFeaturedID: String?

    private var featured: LibraryEntry? {
        if let manualFeaturedID, let match = entries.first(where: { $0.id == manualFeaturedID }) { return match }
        return runningTracker.runningGames.keys.first.flatMap { id in entries.first { $0.id == id } } ?? entries.first
    }
    private var customEntries: [LibraryEntry] { entries.filter { if case .custom = $0 { true } else { false } } }

    private func cycleFeatured(by delta: Int) {
        guard let featured, let currentIndex = entries.firstIndex(where: { $0.id == featured.id }), !entries.isEmpty else { return }
        let newIndex = (currentIndex + delta + entries.count) % entries.count
        manualFeaturedID = entries[newIndex].id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let featured {
                    ZStack(alignment: .bottomLeading) {
                        artView(path: featuredPresentation?.artPath, id: featured.id).frame(maxWidth: .infinity).frame(height: 300).skinArtTreatment().clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom).frame(maxWidth: .infinity, maxHeight: 300)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(runningTracker.runningGames[featured.id] != nil ? "CONTINUE PLAYING" : "FEATURED")
                                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.75))
                            SkinTitleText(text: featured.name, size: 36).foregroundStyle(.white)
                            if let desc = featuredPresentation?.description {
                                Text(desc).font(.body).foregroundStyle(.white.opacity(0.85)).lineLimit(2).frame(maxWidth: 460, alignment: .leading)
                            }
                            Button("View Details") { onOpenDetail(featured) }
                                .buttonStyle(PlaydockButtonStyle(accentOverride: featuredPresentation?.artPath.flatMap { GameArtColor.dominantColor(forImagePath: $0) }))
                        }
                        .padding(32)
                        if entries.count > 1 {
                            HStack {
                                heroNavButton(systemImage: "chevron.left") { cycleFeatured(by: -1) }
                                Spacer()
                                heroNavButton(systemImage: "chevron.right") { cycleFeatured(by: 1) }
                            }
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, maxHeight: 300)
                        }
                    }
                    .task(id: featured.id) { featuredPresentation = await LibraryPresentation.resolve(featured) }
                }
                if !customEntries.isEmpty { shelf("Custom Games", customEntries) }
                shelf("Your Library", entries)
            }
        }
    }

    private func heroNavButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.35), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25)))
        }
        .buttonStyle(.plain)
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

    /// A fixed sidebar column's width, in points - kept as a named constant since both the sidebar
    /// itself and the detail pane's `GeometryReader`-derived width need to agree on it.
    private static let sidebarWidth: CGFloat = 260

    var body: some View {
        // The real, root-cause fix for "sidebar mode is fullscreen and weird": the detail pane's art
        // used `.frame(maxWidth: .infinity, maxHeight: .infinity)` around a `.aspectRatio(.fill)`
        // image with nothing above this layout to pin a concrete bound in either axis (Grid gets one
        // from its own `GeometryReader`; Shelves' hero stays bounded because it pins a *fixed*
        // height, leaving only width flexible) - under a genuinely double-unbounded proposal, the
        // image's own ideal-size negotiation runs away and starves its fixed-260-width sibling
        // almost to nothing, which is exactly what a real screenshot showed: a hairline sliver of
        // sidebar next to art filling the entire window edge-to-edge. A `GeometryReader` here gives
        // every measurement a real, finite number to work from, the same fix already proven for the
        // grid's own overlap bug.
        GeometryReader { geo in
            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(entries) { entry in
                            let isSelected = entry.id == (selectedID ?? entries.first?.id)
                            HStack(spacing: 10) {
                                SmallArtIcon(entry: entry, size: 26, cornerRadius: 6)
                                Text(entry.name).lineLimit(1).fontWeight(isSelected ? .semibold : .regular)
                                Spacer()
                                if runningTracker.runningGames[entry.id] != nil { Circle().fill(.green).frame(width: 7, height: 7) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedID = entry.id }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(.regularMaterial)
                .frame(width: Self.sidebarWidth, height: geo.size.height)

                if let selected {
                    ZStack(alignment: .bottomLeading) {
                        artView(path: presentation?.artPath, id: selected.id)
                            .frame(width: max(0, geo.size.width - Self.sidebarWidth), height: geo.size.height)
                            .skinArtTreatment()
                            .clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 10) {
                            if presentation?.isCustom == true { Text("CUSTOM GAME").font(.caption.bold()).foregroundStyle(.purple) }
                            SkinTitleText(text: selected.name, size: 30).foregroundStyle(.white)
                            if let desc = presentation?.description {
                                Text(desc).font(.body).foregroundStyle(.white.opacity(0.85)).lineLimit(3).frame(maxWidth: 440, alignment: .leading)
                            }
                            Button("View Details") { onOpenDetail(selected) }
                                .buttonStyle(PlaydockButtonStyle(accentOverride: presentation?.artPath.flatMap { GameArtColor.dominantColor(forImagePath: $0) }))
                        }
                        .padding(32)
                    }
                    .frame(width: max(0, geo.size.width - Self.sidebarWidth), height: geo.size.height)
                    .clipped()
                    .task(id: selected.id) { presentation = await LibraryPresentation.resolve(selected) }
                } else {
                    Color.clear.frame(width: max(0, geo.size.width - Self.sidebarWidth), height: geo.size.height)
                }
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
                        SmallArtIcon(entry: entry, size: 30, cornerRadius: 6)
                        HStack(spacing: 6) {
                            SkinTitleText(text: entry.name, size: 15)
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
                        .foregroundStyle(f == filter ? Color.accentColor : .primary)
                        .padding(.horizontal, 14).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                        .background(f == filter ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
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
                        LibraryEntryTile(entry: entry, width: 154, height: 210, artShape: .portrait) { onOpenDetail(entry) }
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
        VStack(alignment: .leading, spacing: 20) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(entries) { entry in
                        let isFocused = entry.id == (focused ?? entries.first?.id)
                        LibraryEntryTile(entry: entry, width: isFocused ? 230 : 185, height: isFocused ? 300 : 240, artShape: .portrait) {
                            // Hover already sets focus for a real mouse/trackpad, so by the time a
                            // click lands the tile is already focused and can open straight away -
                            // "carasoul should track mouse focus," and this also fixes a genuine
                            // click-swallowing bug the old two-step tap dance had: growing a tile on
                            // its first tap reflows every tile after it in the row, so a *second*
                            // click aimed at the same screen position could land on a neighbor that
                            // had shifted into it instead of the now-larger focused tile.
                            onOpenDetail(entry)
                        }
                        .scaleEffect(isFocused ? 1 : 0.96)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: focused)
                        .onHover { isHovering in
                            if isHovering { focused = entry.id }
                        }
                    }
                }
                .padding(.horizontal, 32).padding(.top, 20)
            }
            // A fixed-height reserved panel (not conditional on data already being loaded) so the
            // row below never jumps when focus changes or while a fetch is in flight - and, unlike
            // the version this replaced, the `.task` that actually fetches `presentation` is
            // attached to a view that's *always* present, not one gated behind the very data it's
            // supposed to produce. That inversion was a real deadlock: `if let desc =
            // presentation?.description { Text(desc).task { presentation = ... } }` can never run
            // its own fetch, because the `if` guarding it requires the fetch's result to already
            // exist - so the info panel never appeared at all, for any game, ever.
            Group {
                if let focusedEntry {
                    VStack(alignment: .leading, spacing: 6) {
                        SkinTitleText(text: focusedEntry.name, size: 20)
                        if let genre = presentation?.genre {
                            Text(genre.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                        }
                        if let desc = presentation?.description {
                            Text(desc).font(.body).foregroundStyle(.secondary).lineLimit(3).frame(maxWidth: 560, alignment: .leading)
                        }
                    }
                    .task(id: focusedEntry.id) { presentation = await LibraryPresentation.resolve(focusedEntry) }
                }
            }
            .frame(minHeight: 90, alignment: .top)
            .padding(.horizontal, 32)
            Spacer()
        }
    }
}

// MARK: - Layout F: Spotlight (magazine-style feature + grid, real per-skin craft)

/// The structure behind the web-rendered Editorial *skin* that impressed live - "damn i love the
/// editorial appearence. make it into a layout one and make sure every other appearence is able to
/// be the same quality in the skin for the editorial layout" - split out as a real, independent
/// *layout* (this file's usual axis: structure, not look) so any of the ten skins can use it, not
/// just Editorial's own CSS. Uses the same `cardSurface()`/`tileSurface()`/`SkinTitleText`/
/// `SkinBackground` machinery every other layout here already does, so it inherits the exact same
/// real per-skin card craft (Cyber's cut corners, Brutalist/Pixel's hard shadow, Soft's neumorphic
/// highlight, Glass/Vapor's translucency) rather than being tied to one skin's own look.
struct LibrarySpotlightLayout: View {
    let entries: [LibraryEntry]
    let onOpenDetail: (LibraryEntry) -> Void
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    @LocalState private var featuredPresentation: LibraryPresentation?
    /// Sticks once someone browses manually - see `LibraryShelvesLayout`'s identical field for why.
    @LocalState private var manualFeaturedID: String?

    private var featured: LibraryEntry? {
        if let manualFeaturedID, let match = entries.first(where: { $0.id == manualFeaturedID }) { return match }
        return runningTracker.runningGames.keys.first.flatMap { id in entries.first { $0.id == id } } ?? entries.first
    }
    private var featuredAccent: Color? { featuredPresentation?.artPath.flatMap { GameArtColor.dominantColor(forImagePath: $0) } }
    private var rest: [LibraryEntry] {
        guard let featured else { return entries }
        return entries.filter { $0.id != featured.id }
    }
    private var featuredIndex: Int {
        guard let featured else { return 0 }
        return (entries.firstIndex(where: { $0.id == featured.id }) ?? 0) + 1
    }

    private func cycleFeatured(by delta: Int) {
        guard let featured, let currentIndex = entries.firstIndex(where: { $0.id == featured.id }), !entries.isEmpty else { return }
        let newIndex = (currentIndex + delta + entries.count) % entries.count
        manualFeaturedID = entries[newIndex].id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let featured {
                    HStack(alignment: .center, spacing: 36) {
                        artView(path: featuredPresentation?.artPath, id: featured.id)
                            .frame(width: 420, height: 260)
                            .skinArtTreatment()
                            .tileSurface(accentOverride: featuredAccent)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(runningTracker.runningGames[featured.id] != nil ? "CURRENTLY PLAYING" : "FEATURED")
                                .font(.caption.weight(.bold)).foregroundStyle(Color.accentColor)
                            SkinTitleText(text: featured.name, size: 38)
                            if let desc = featuredPresentation?.description {
                                Text(desc).font(.body).foregroundStyle(.secondary).lineLimit(4).frame(maxWidth: 480, alignment: .leading)
                            }
                            HStack(spacing: 14) {
                                Button("View Details") { onOpenDetail(featured) }.buttonStyle(PlaydockButtonStyle(accentOverride: featuredAccent))
                                if entries.count > 1 {
                                    HStack(spacing: 8) {
                                        spotlightNavButton("chevron.left") { cycleFeatured(by: -1) }
                                        Text("\(featuredIndex) / \(entries.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                        spotlightNavButton("chevron.right") { cycleFeatured(by: 1) }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(32)
                    .task(id: featured.id) { featuredPresentation = await LibraryPresentation.resolve(featured) }
                }
                if !rest.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ALSO IN YOUR COLLECTION").font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.horizontal, 32)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 20)], spacing: 24) {
                            ForEach(rest) { entry in
                                LibraryEntryTile(entry: entry, width: 210, height: 130) { onOpenDetail(entry) }
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }

    private func spotlightNavButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.callout.weight(.semibold)).frame(width: 28, height: 28)
        }
        .buttonStyle(PlaydockButtonStyle(prominent: false))
    }
}
