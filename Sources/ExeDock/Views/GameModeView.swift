import SwiftUI
import AppKit

/// The games grid's own measured width - the grid uses `.adaptive(minimum:maximum:)` columns, so
/// how many actually render depends on the window's current width, not a fixed number. Read via
/// `GameModeView`'s `gridWidth` state so controller D-pad up/down can jump a full row.
private struct GridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Every controller-focusable spot on the main dashboard - the toolbar (Refresh/Settings), a card
/// in the grid, or the floating Steam icon - covering "every clickable thing," not just the grid.
private enum DashboardFocusTarget: Equatable {
    case toolbar(Int) // 0 = Refresh, 1 = Settings
    case card(Int)
    case steamIcon
}

struct GameModeView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    @ObservedObject private var controllerObserver = ControllerObserver.shared
    @AppStorage("com.exedock.advancedMode") private var isAdvancedMode = false
    @LocalState private var search = ""
    @LocalState private var showingSettingsSheet = false
    @LocalState private var showingAddGameSheet = false
    @LocalState private var sortOption: GameSortOption = .name
    @LocalState private var launchOverlayGame: SteamGame?
    @LocalState private var showingControllerMode = false
    @LocalState private var detailGame: SteamGame?
    @LocalState private var detailCustomGame: CustomGame?
    /// Everywhere a controller's D-pad can currently be focused on the dashboard - the toolbar
    /// (Refresh/Settings), a card in the grid, or the floating Steam icon. `nil` until the first
    /// D-pad press (mouse-only browsing shows no ring at all).
    @LocalState private var focusedTarget: DashboardFocusTarget?
    /// The grid's own measured width, used to figure out how many columns are actually rendered
    /// right now (the grid uses `.adaptive(minimum:maximum:)`, so the true column count depends on
    /// window width, not a fixed number) - needed so D-pad up/down jumps a full row instead of just
    /// "next card." See `gridColumnCount`.
    @LocalState private var gridWidth: CGFloat = 0

    private enum GameSortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case recentlyUpdated = "Recently Updated"
        var id: String { rawValue }
    }

    private var filteredGames: [SteamGame] {
        let filtered = search.isEmpty ? model.steamGames : model.steamGames.filter { $0.name.localizedCaseInsensitiveContains(search) }
        switch sortOption {
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recentlyUpdated:
            return filtered.sorted { ($0.lastUpdated ?? .distantPast) > ($1.lastUpdated ?? .distantPast) }
        }
    }

    /// The unified grid content - Steam games plus manually-imported custom games, searched and
    /// sorted together. Steam-only concerns (the launch overlay, dashboard backdrop theming) stay
    /// keyed off `model.steamGames`/`filteredGames` directly; this is specifically what the grid
    /// itself, and controller focus over it, iterate.
    private var libraryEntries: [LibraryEntry] {
        let all = model.steamGames.map(LibraryEntry.steam) + model.customGames.map(LibraryEntry.custom)
        let filtered = search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) }
        switch sortOption {
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recentlyUpdated:
            return filtered.sorted { $0.sortDate > $1.sortDate }
        }
    }

    var body: some View {
        if !model.isGameModeUnlocked {
            lockedState
        } else {
            dashboard
        }
    }

    // MARK: - Locked

    private var lockedState: some View {
        VStack(spacing: 24) {
            if model.isInstallingSteam {
                LoadingDotsView(message: installingMessage)
            } else {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Your games live here once Steam is installed.")
                    .font(.title2)
                Button("Install & Run Steam") {
                    model.installAndRunSteam()
                }
                .buttonStyle(.big)
                .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var installingMessage: String {
        if case .installing(let message) = model.steamStatus { return message }
        return "Installing Steam…"
    }

    // MARK: - Dashboard

    /// The game to theme the dashboard's own backdrop after - not hover/selection (constantly
    /// re-theming while just browsing the grid would be distracting), but whichever game is
    /// actually running right now, so the effect means something. The launch overlay covers this at
    /// full intensity while starting up; this is the subtler version that lingers behind the normal
    /// dashboard once that overlay dismisses.
    private var themedGame: SteamGame? {
        guard let runningAppID = runningTracker.runningGames.keys.first else { return nil }
        return model.steamGames.first { $0.appID == runningAppID }
    }

    /// Everything `RunningGameTracker` should watch for "is it running" - Steam games (their own
    /// install-dir fragment, unchanged) plus custom games (their exe's own containing folder name,
    /// since they aren't necessarily installed anywhere near a `steamapps` folder at all).
    private var watchTargets: [(id: String, matchFragment: String)] {
        model.steamGames.map { (id: $0.appID, matchFragment: "steamapps/common/\($0.installDir)") }
            + model.customGames.map { (id: $0.id, matchFragment: (($0.exePath as NSString).deletingLastPathComponent as NSString).lastPathComponent) }
    }

    private var dashboard: some View {
        ZStack {
            if let themedGame {
                DashboardBackdropView(game: themedGame)
                    .transition(.opacity)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                header
                if controllerObserver.isConnected && !controllerObserver.bannerDismissed {
                    controllerBanner
                }
                Divider()
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            searchBar
                            gamesGrid
                        }
                        .padding(24)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(key: GridWidthKey.self, value: geometry.size.width)
                            }
                        )
                    }
                    .onPreferenceChange(GridWidthKey.self) { gridWidth = $0 }
                    .onChange(of: focusedTarget) { target in
                        guard case .card(let index) = target, libraryEntries.indices.contains(index) else { return }
                        withAnimation { scrollProxy.scrollTo(libraryEntries[index].id, anchor: .center) }
                    }
                }
            }

            steamFloatingIcon
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(24)
                .allowsHitTesting(detailGame == nil && detailCustomGame == nil && launchOverlayGame == nil && !showingControllerMode)

            if let detailGame {
                GameDetailView(game: detailGame, isAdvancedMode: isAdvancedMode) {
                    self.detailGame = nil
                } onLaunch: {
                    self.detailGame = nil
                    launchOverlayGame = detailGame
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(1)
            }

            if let detailCustomGame {
                CustomGameDetailView(game: detailCustomGame, isAdvancedMode: isAdvancedMode) {
                    self.detailCustomGame = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(1)
            }

            if let launchOverlayGame {
                LaunchOverlayView(game: launchOverlayGame, config: model.config(for: launchOverlayGame))
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(1)
            }

            if showingControllerMode {
                ControllerModeView {
                    showingControllerMode = false
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.launchingTarget)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: launchOverlayGame?.appID)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: detailGame?.appID)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: detailCustomGame?.id)
        .animation(.easeInOut(duration: 0.4), value: themedGame?.appID)
        .animation(.easeInOut(duration: 0.25), value: showingControllerMode)
        .sheet(isPresented: $showingSettingsSheet) {
            DefaultSettingsSheet(isAdvancedMode: $isAdvancedMode)
        }
        .sheet(isPresented: $showingAddGameSheet) {
            AddGameSheet()
        }
        .onChange(of: model.steamGames) { _ in
            runningTracker.syncWatchedGames(watchTargets)
        }
        .onChange(of: model.customGames) { _ in
            runningTracker.syncWatchedGames(watchTargets)
        }
        .onAppear {
            runningTracker.syncWatchedGames(watchTargets)
        }
        .onChange(of: controllerObserver.directionPress?.token) { _ in
            guard isDashboardTheActiveControllerLayer, let direction = controllerObserver.directionPress?.direction else { return }
            moveFocus(direction)
        }
        .onChange(of: controllerObserver.primaryPress) { _ in
            guard isDashboardTheActiveControllerLayer else { return }
            activateFocusedTarget()
        }
        .onChange(of: runningTracker.runningGames) { running in
            // The overlay's honest dismiss signal: the game process actually showed up. Playdock
            // can't know when a Steam-mediated game *closes* (Steam owns that child process), so
            // there's no equivalent "and disappears" trigger here - see RunningGameTracker's own
            // doc comment for why this is a best-effort heuristic, not a real IPC hook.
            if let launchOverlayGame, running[launchOverlayGame.appID] != nil {
                self.launchOverlayGame = nil
            }
        }
        .onChange(of: launchOverlayGame?.appID) { appID in
            guard let appID else { return }
            Task {
                try? await Task.sleep(for: .seconds(20))
                if launchOverlayGame?.appID == appID {
                    launchOverlayGame = nil
                }
            }
        }
    }

    private var controllerBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill")
            Text("Controller connected")
            Spacer()
            Button("Enter Controller Mode") {
                showingControllerMode = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            Button {
                controllerObserver.bannerDismissed = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.12))
    }

    /// Deliberately tiny - "insanely small and unobtrusive," per live feedback, so the games grid
    /// gets as much of the window as possible. Just enough to identify whose library this is and
    /// offer Refresh/Settings; everything else (art, ratings, controller navigation) lives in the
    /// grid and the Game Detail view instead of competing for space up here.
    private var header: some View {
        HStack(spacing: 10) {
            profileAvatar
            Text(model.steamProfile?.personaName ?? "Steam")
                .font(.headline)
            Text(model.steamGames.isEmpty ? "No games installed" : "\(model.steamGames.count) game\(model.steamGames.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            headerIconButton(systemImage: "plus", help: "Add Game", isFocused: controllerObserver.isConnected && focusedTarget == .toolbar(0)) {
                showingAddGameSheet = true
            }
            .keyboardShortcut("n", modifiers: .command)

            headerIconButton(systemImage: "arrow.clockwise", help: "Refresh", isFocused: controllerObserver.isConnected && focusedTarget == .toolbar(1)) {
                model.refreshSteamGames()
                model.refreshSteamProfile()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isLoadingSteamGames)

            headerIconButton(systemImage: "gearshape", help: "Settings", isFocused: controllerObserver.isConnected && focusedTarget == .toolbar(2)) {
                showingSettingsSheet = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// A soft rounded-square, icon-only button - used for the header's secondary actions
    /// (Refresh/Settings), and generally sized big enough to be an easy, unambiguous target for a
    /// controller cursor as well as a mouse.
    private func headerIconButton(systemImage: String, help: String, isFocused: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.bordered)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focusRing(isFocused)
        .help(help)
    }

    /// The way to open Steam itself - double-click, the same gesture as opening anything else on a
    /// Mac. Floats over the bottom-right corner of the whole dashboard (moved off a big centered
    /// tile that used to take up nearly half the screen, then off the header entirely - "the steam
    /// icon be at the bottom right," per live feedback), always reachable without competing for
    /// space with anything else in the layout. Uses Steam's own real icon when the native Mac
    /// Steam.app is present on this machine (legitimately already installed by the user, same as
    /// how AppIconProvider reads any other already-installed app's icon) - falling back to an
    /// in-house glyph otherwise, since NSWorkspace can't extract an icon from a .exe buried in a
    /// private, never-Finder-indexed Wine bottle. Shows exactly one spinner, right on the icon,
    /// while launching.
    private static let nativeSteamAppPath = "/Applications/Steam.app"

    private var steamFloatingIcon: some View {
        let isLaunching = model.launchingTarget == .steam
        return ZStack {
            steamIcon(size: 200, cornerRadius: 44)
                .opacity(isLaunching ? 0.3 : 1)
            if isLaunching {
                ProgressView().controlSize(.large).scaleEffect(1.8)
            }
        }
        .frame(width: 200, height: 200)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 44))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 44))
        // No .pressPush()/other gesture-based press effect here on purpose - a real bug, found
        // live: a simultaneous zero-distance DragGesture (which is what that press effect used to
        // detect "pressed") competing with .onTapGesture(count: 2) on the same view could silently
        // swallow the double-click recognition entirely, so double-clicking did nothing at all - no
        // spinner, no launch. The isLaunching-driven opacity/spinner above is the only feedback
        // this needs.
        .onTapGesture(count: 2) {
            model.openSteamClient()
        }
        .allowsHitTesting(model.launchingTarget == nil)
        .focusRing(controllerObserver.isConnected && focusedTarget == .steamIcon)
        .help(isLaunching ? "Launching Steam…" : "Double-click to open Steam")
    }

    @ViewBuilder
    private func steamIcon(size: CGFloat, cornerRadius: CGFloat) -> some View {
        if FileManager.default.fileExists(atPath: Self.nativeSteamAppPath) {
            Image(nsImage: AppIconProvider.icon(forPath: Self.nativeSteamAppPath))
                .resizable()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.53, green: 0.33, blue: 0.96), Color(red: 0.16, green: 0.18, blue: 0.52)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(.white)
                )
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        }
    }

    private var profileAvatar: some View {
        Group {
            if let avatarPath = model.steamProfile?.avatarPath, let image = LocalImageCache.image(atPath: avatarPath) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .hoverSpin()
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search your games", text: $search)
                    .textFieldStyle(.plain)
                    .font(.title3)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            Picker("Sort", selection: $sortOption) {
                ForEach(GameSortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .frame(maxWidth: 220)
        }
    }

    /// Card size scales with how many games are actually in the library - a lone game (or a
    /// handful) gets big, prominent cards instead of sitting tiny in a corner of a mostly-empty
    /// window; a large library steps down to a denser grid so more fits per screen. Re-evaluated
    /// live off `libraryEntries.count`, so it also reacts to search narrowing the visible set.
    private var cardSizeTier: (minWidth: CGFloat, maxWidth: CGFloat, artworkHeight: CGFloat) {
        switch libraryEntries.count {
        case 0...2: return (480, 640, 260)
        case 3...6: return (360, 440, 190)
        case 7...15: return (280, 340, 150)
        default: return (240, 280, 130)
        }
    }

    private var gridColumns: [GridItem] {
        let tier = cardSizeTier
        return [GridItem(.adaptive(minimum: tier.minWidth, maximum: tier.maxWidth), spacing: 20)]
    }

    /// How many columns `.adaptive(minimum:maximum:)` is actually rendering right now, worked out
    /// from the grid's own measured width the same way SwiftUI itself would - needed so controller
    /// D-pad up/down can jump a full row instead of just "next card" in array order.
    private var gridColumnCount: Int {
        let spacing: CGFloat = 20
        let minWidth = cardSizeTier.minWidth
        guard gridWidth > 0, minWidth > 0 else { return 1 }
        return max(1, Int((gridWidth + spacing) / (minWidth + spacing)))
    }

    /// Only active while nothing's covering the dashboard (no Game Detail view, no Controller Mode
    /// carousel) - both of those own the same D-pad/A stream the instant they're shown, per
    /// `ControllerObserver`'s "single owner, self-filtering subscribers" design.
    private var isDashboardTheActiveControllerLayer: Bool {
        detailGame == nil && detailCustomGame == nil && !showingControllerMode
    }

    /// Real 2D movement across every focusable spot on the dashboard: the toolbar row above the
    /// grid, the grid itself (up/down jump a full row via `gridColumnCount`, left/right stop at
    /// row edges instead of wrapping into the row above/below), and the floating Steam icon beyond
    /// the grid's last row.
    private func moveFocus(_ direction: ControllerDirection) {
        guard let current = focusedTarget else {
            focusedTarget = libraryEntries.isEmpty ? .toolbar(0) : .card(0)
            return
        }
        switch current {
        case .toolbar(let toolbarIndex):
            switch direction {
            case .left: focusedTarget = .toolbar(max(0, toolbarIndex - 1))
            case .right: focusedTarget = .toolbar(min(2, toolbarIndex + 1))
            case .down: focusedTarget = libraryEntries.isEmpty ? current : .card(0)
            case .up: break
            }
        case .card(let index):
            let columns = gridColumnCount
            switch direction {
            case .left:
                guard index % columns != 0 else { return }
                focusedTarget = .card(index - 1)
            case .right:
                guard index % columns != columns - 1, index + 1 < libraryEntries.count else { return }
                focusedTarget = .card(index + 1)
            case .up:
                focusedTarget = index < columns ? .toolbar(0) : .card(index - columns)
            case .down:
                let next = index + columns
                focusedTarget = next < libraryEntries.count ? .card(next) : .steamIcon
            }
        case .steamIcon:
            if direction == .up {
                focusedTarget = libraryEntries.isEmpty ? .toolbar(0) : .card(libraryEntries.count - 1)
            }
        }
    }

    private func activateFocusedTarget() {
        switch focusedTarget {
        case .toolbar(0):
            showingAddGameSheet = true
        case .toolbar(1):
            guard !model.isLoadingSteamGames else { return }
            model.refreshSteamGames()
            model.refreshSteamProfile()
        case .toolbar:
            showingSettingsSheet = true
        case .card(let index):
            guard libraryEntries.indices.contains(index) else { return }
            switch libraryEntries[index] {
            case .steam(let game): detailGame = game
            case .custom(let game): detailCustomGame = game
            }
        case .steamIcon:
            guard model.launchingTarget == nil else { return }
            model.openSteamClient()
        case nil:
            break
        }
    }

    @ViewBuilder
    private var gamesGrid: some View {
        if model.isLoadingSteamGames && model.steamGames.isEmpty && model.customGames.isEmpty {
            // Shimmering placeholders in the exact grid the real cards will land in - reads as a
            // proper dashboard loading in, not just "something, somewhere, is thinking."
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(0..<6, id: \.self) { _ in GameCardSkeleton() }
            }
        } else if model.steamGames.isEmpty && model.customGames.isEmpty {
            emptyGamesState
        } else if libraryEntries.isEmpty {
            Text("No games match \u{201C}\(search)\u{201D}.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(Array(libraryEntries.enumerated()), id: \.element.id) { index, entry in
                    let isFocused = controllerObserver.isConnected && focusedTarget == .card(index)
                    switch entry {
                    case .steam(let game):
                        GameCardView(
                            game: game, isAdvancedMode: isAdvancedMode, artworkHeight: cardSizeTier.artworkHeight,
                            isFocused: isFocused
                        ) {
                            launchOverlayGame = game
                        } onOpenDetail: {
                            detailGame = game
                        }
                    case .custom(let customGame):
                        CustomGameCardView(
                            game: customGame, isAdvancedMode: isAdvancedMode, artworkHeight: cardSizeTier.artworkHeight,
                            isFocused: isFocused
                        ) {
                            detailCustomGame = customGame
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.steamGames)
            .animation(.easeInOut(duration: 0.2), value: model.customGames)
            .animation(.easeInOut(duration: 0.2), value: cardSizeTier.maxWidth)
        }
    }

    private var emptyGamesState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No games installed yet")
                .font(.title3).bold()
            Text("Install something from the Steam store, or use \u{201C}+\u{201D} above to add a game you already have.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Game card

private struct GameCardView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    let game: SteamGame
    let isAdvancedMode: Bool
    let artworkHeight: CGFloat
    let isFocused: Bool
    let onLaunch: () -> Void
    let onOpenDetail: () -> Void
    @LocalState private var storeInfo: SteamStoreInfo?
    @LocalState private var showingSettings = false
    @LocalState private var isHoveringArtwork = false

    private var hasCustomSettings: Bool { model.perGameConfigs[game.appID] != nil }
    private var runningInfo: RunningProcessInfo? { runningTracker.runningGames[game.appID] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 4) {
                    Text(game.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .help(developerHelpText)
                    Spacer()
                    if isAdvancedMode {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: hasCustomSettings ? "slider.horizontal.3" : "gearshape")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .help(hasCustomSettings ? "Custom settings" : "Game settings")
                        .popover(isPresented: $showingSettings) {
                            GameSettingsPopover(game: game)
                        }
                    }
                }
                if let description = storeInfo?.shortDescription {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                detailsRow
                if let runningInfo {
                    runningBadge(runningInfo)
                } else {
                    openDetailHint
                }
            }
            .padding(20)
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .focusRing(isFocused)
        // Tapping the card opens the full Game Detail view rather than launching straight away -
        // "it should go into full screen before you can launch," per live feedback, so the grid
        // card itself is just an entry point now. A plain single-tap gesture on this container is
        // safe alongside the gearshape Button above (SwiftUI routes a tap within a nested Button's
        // own bounds to that button first) - this is a different situation from the earlier
        // Steam-tile bug, which was specifically a *simultaneous* zero-distance DragGesture
        // competing with a double-tap recognizer on the very same view.
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { onOpenDetail() }
        .contextMenu {
            Button {
                onOpenDetail()
            } label: {
                Label("View Details", systemImage: "info.circle")
            }
            if runningInfo == nil {
                Button {
                    onLaunch()
                    model.launchSteamGame(game)
                } label: {
                    Label("Launch", systemImage: "play.fill")
                }
                .disabled(model.launchingTarget != nil)
            }
            Divider()
            Button {
                model.revealInFinder(installFolderPath)
            } label: {
                Label("Reveal Install Folder", systemImage: "folder")
            }
            Button {
                model.openStorePage(for: game)
            } label: {
                Label("View Store Page", systemImage: "safari")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(game.appID, forType: .string)
            } label: {
                Label("Copy App ID", systemImage: "doc.on.doc")
            }
        }
        .task(id: game.appID) {
            storeInfo = await SteamStoreInfoCache.shared.info(for: game.metadataAppID)
        }
        .onHover { isHovering in
            if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var installFolderPath: String {
        (SteamInstaller.steamBottle.driveCPath as NSString)
            .appendingPathComponent("Program Files (x86)/Steam/steamapps/common")
            .appending("/\(game.installDir)")
    }

    private var detailsRow: some View {
        HStack(spacing: 8) {
            if let score = storeInfo?.metacriticScore {
                metacriticBadge(score)
            }
            if let genre = storeInfo?.genres.first {
                Text(genre)
            }
            if let size = game.sizeOnDisk {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            if let build = game.buildID {
                Text("Build \(build)")
            }
            Text(engineBadgeText)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    /// Steam's own color convention: green for "generally favorable," yellow for "mixed," red for
    /// "generally unfavorable" - the same ranges Metacritic/Steam use on their own store pages.
    private func metacriticBadge(_ score: Int) -> some View {
        Text("\(score)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(metacriticColor(score), in: RoundedRectangle(cornerRadius: 4))
    }

    private func metacriticColor(_ score: Int) -> Color {
        switch score {
        case 75...: return .green
        case 50..<75: return .yellow
        default: return .red
        }
    }

    private var developerHelpText: String {
        guard let storeInfo, !storeInfo.developers.isEmpty else { return game.name }
        var parts = ["By \(storeInfo.developers.joined(separator: ", "))"]
        if let releaseDate = storeInfo.releaseDate { parts.append("Released \(releaseDate)") }
        return parts.joined(separator: " · ")
    }

    private var engineBadgeText: String {
        let config = model.config(for: game)
        return config.d3dMetal ? "D3DMetal" : (config.dxvk ? "DXVK" : (config.dxmt ? "DXMT" : "Default"))
    }

    /// Replaces the Launch button while `RunningGameTracker` sees this game's process - a
    /// minute-granularity elapsed time (no need for per-second ticking on a "how long has this been
    /// running" label), ticked by `TimelineView` rather than a manually managed Timer.
    private func runningBadge(_ info: RunningProcessInfo) -> some View {
        TimelineView(.periodic(from: info.startedAt, by: 60)) { context in
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Running \(elapsedString(from: info.startedAt, to: context.date))")
                    .font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func elapsedString(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    /// Replaces the old inline Launch button - launching now only happens from the full Game Detail
    /// view, reached by tapping the card, so this is just a quiet affordance instead of an action.
    private var openDetailHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
            Text("Click for details")
        }
        .font(.title3.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private var artwork: some View {
        Group {
            if let headerPath = storeInfo?.headerImagePath, let image = LocalImageCache.image(atPath: headerPath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(isHoveringArtwork ? 1.06 : 1.0)
                    .animation(.easeOut(duration: 0.3), value: isHoveringArtwork)
            } else {
                // Not a real exe-icon lookup on purpose - NSWorkspace can't extract one from a file
                // buried in a private, never-Finder-indexed Wine bottle, so it just renders blank.
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: artworkHeight * 0.3))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.15))
            }
        }
        .frame(height: artworkHeight)
        .clipped()
        .onHover { isHoveringArtwork = $0 }
    }
}

// MARK: - Game detail

/// The full "click into a game" detail view - a first-class, Steam-store-like page (big art, genre,
/// rating, developer, release date, description) reached by tapping a card. Launching now happens
/// from here rather than directly off the small grid card - "it should go into full screen before
/// you can launch," per live feedback. Not a real `matchedGeometryEffect` hero animation from the
/// exact card tapped, for the same reason `LaunchOverlayView` doesn't attempt one either:
/// `GameCardView` lives inside a `LazyVGrid`/`ScrollView`, where an off-screen card may not have a
/// measured frame to animate from. A scale+fade transition (applied by the caller, matching
/// `LaunchOverlayView`'s own) reads as the card "growing" into this view without that risk.
/// The actions `actionRow` can show, in display order - used both to render the row and to drive
/// controller focus over it (see `GameDetailView`'s `.onChange(of: controllerObserver.*)` handlers).
private enum DetailAction: Equatable {
    case launch, settings, reveal, storePage
}

struct GameDetailView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    @ObservedObject private var controllerObserver = ControllerObserver.shared
    let game: SteamGame
    let isAdvancedMode: Bool
    let onClose: () -> Void
    let onLaunch: () -> Void
    @LocalState private var storeInfo: SteamStoreInfo?
    @LocalState private var showingSettings = false
    /// Which action a controller's D-pad currently has highlighted - only ever shown/used while a
    /// controller is actually connected (see `availableActions`'s call sites), so mouse-only use
    /// never sees a stray focus ring.
    @LocalState private var focusedActionIndex = 0

    private var runningInfo: RunningProcessInfo? { runningTracker.runningGames[game.appID] }
    private var hasCustomSettings: Bool { model.perGameConfigs[game.appID] != nil }

    /// Exactly the same conditions `actionRow` already uses to decide what to show - kept as one
    /// list so controller focus always lines up with what's actually on screen (e.g. never
    /// highlights a Settings button that isn't rendered outside Advanced Mode).
    private var availableActions: [DetailAction] {
        var actions: [DetailAction] = []
        if runningInfo == nil { actions.append(.launch) }
        if isAdvancedMode { actions.append(.settings) }
        actions.append(.reveal)
        actions.append(.storePage)
        return actions
    }

    private func isFocused(_ action: DetailAction) -> Bool {
        controllerObserver.isConnected && availableActions[safe: focusedActionIndex] == action
    }

    private func moveActionFocus(_ direction: ControllerDirection) {
        guard !availableActions.isEmpty else { return }
        switch direction {
        case .left, .up: focusedActionIndex = max(0, focusedActionIndex - 1)
        case .right, .down: focusedActionIndex = min(availableActions.count - 1, focusedActionIndex + 1)
        }
    }

    private func activateFocusedAction() {
        switch availableActions[safe: focusedActionIndex] {
        case .launch:
            onLaunch()
            model.launchSteamGame(game)
        case .settings:
            showingSettings = true
        case .reveal:
            model.revealInFinder(installFolderPath)
        case .storePage:
            model.openStorePage(for: game)
        case nil:
            break
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            VStack(alignment: .leading, spacing: 0) {
                closeButton
                ScrollView {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            // The full "About This Game" copy when it's there (real store text,
                            // not just the one-line card blurb) - falls back to the short
                            // description for anything fetched before this field existed, or for
                            // entries with no fuller write-up at all.
                            if let description = storeInfo?.aboutTheGame ?? storeInfo?.shortDescription {
                                Text(description)
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            metaRow
                            actionRow
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if hasPhotos {
                            photoColumn
                                .frame(width: 260)
                        }
                    }
                    .padding(32)
                    // The double .frame() is deliberate, not redundant: the first caps the content
                    // row's own width so it stays readable at 820pt; the second then re-expands
                    // that capped block to fill whatever width the ScrollView actually has and
                    // re-applies leading alignment *within* that full width. A single
                    // `.frame(maxWidth: 820, alignment: .leading)` only caps the view's own size -
                    // it doesn't reliably left-anchor it against a wider ancestor, which is exactly
                    // what put this content off-screen entirely: confirmed live, content rendering
                    // well past the left edge of the window with no way to reach the close button.
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .colorScheme(.dark)
        .task(id: game.appID) {
            storeInfo = await SteamStoreInfoCache.shared.info(for: game.metadataAppID)
        }
        .onExitCommand { onClose() }
        // GameDetailView always treats itself as the active controller-input layer while it's
        // mounted - it's rendered above everything else wherever it appears (a direct card tap, or
        // ControllerModeView's own drill-down), so there's nothing above it to defer to.
        .onChange(of: controllerObserver.directionPress?.token) { _ in
            guard let direction = controllerObserver.directionPress?.direction else { return }
            moveActionFocus(direction)
        }
        .onChange(of: controllerObserver.primaryPress) { _ in
            activateFocusedAction()
        }
        .onChange(of: controllerObserver.secondaryPress) { _ in
            onClose()
        }
    }

    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white, .black.opacity(0.4))
        }
        .buttonStyle(.plain)
        .padding(24)
        .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let path = storeInfo?.backgroundImagePath ?? storeInfo?.headerImagePath, let image = LocalImageCache.image(atPath: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 50)
                .overlay(Color.black.opacity(0.6))
                .ignoresSafeArea()
        } else {
            LinearGradient(colors: [Color.accentColor.opacity(0.5), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(game.name)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            if storeInfo?.metacriticScore != nil || !(storeInfo?.genres.isEmpty ?? true) {
                HStack(spacing: 10) {
                    if let score = storeInfo?.metacriticScore {
                        metacriticBadge(score)
                    }
                    ForEach(storeInfo?.genres.prefix(3) ?? [], id: \.self) { genre in
                        tag(genre)
                    }
                }
            }
            if !subtitleLine.isEmpty {
                Text(subtitleLine)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    /// True whenever there's actually something to put in `photoColumn` - governs whether the
    /// right-hand photo column renders at all, so a game with no fetched art doesn't leave an empty
    /// gap on the right.
    private var hasPhotos: Bool {
        storeInfo?.headerImagePath != nil || !(storeInfo?.screenshotPaths.isEmpty ?? true)
    }

    /// Every "game photo" (header art, then screenshots) stacked in one column on the right side of
    /// the view - "for game photos... move to the right," per live feedback. Each image sizes
    /// itself to the column's own fixed width via `.aspectRatio(contentMode: .fit)`, which can never
    /// crop *or* stretch an image regardless of its real aspect ratio - the fix for a real, separate
    /// complaint ("it looks squashed") that a fixed width+height frame with `.fill` risked for
    /// screenshots, whose aspect ratio doesn't always match the header art's.
    private var photoColumn: some View {
        VStack(spacing: 12) {
            if let path = storeInfo?.headerImagePath, let image = LocalImageCache.image(atPath: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15)))
            }
            ForEach(storeInfo?.screenshotPaths ?? [], id: \.self) { path in
                if let image = LocalImageCache.image(atPath: path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    /// Same green/yellow/red convention Steam's own store pages use for Metacritic scores.
    private func metacriticBadge(_ score: Int) -> some View {
        Text("\(score)")
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(metacriticColor(score), in: RoundedRectangle(cornerRadius: 5))
    }

    private func metacriticColor(_ score: Int) -> Color {
        switch score {
        case 75...: return .green
        case 50..<75: return .yellow
        default: return .red
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }

    private var subtitleLine: String {
        var parts: [String] = []
        if let developers = storeInfo?.developers, !developers.isEmpty {
            parts.append("By \(developers.joined(separator: ", "))")
        }
        if let releaseDate = storeInfo?.releaseDate {
            parts.append("Released \(releaseDate)")
        }
        return parts.joined(separator: "  ·  ")
    }


    private var metaRow: some View {
        HStack(spacing: 28) {
            if let size = game.sizeOnDisk {
                metaItem("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            if let build = game.buildID {
                metaItem("Build", build)
            }
            metaItem("Engine", engineBadgeText)
            if let publisher = storeInfo?.publishers.first, publisher != storeInfo?.developers.first {
                metaItem("Publisher", publisher)
            }
        }
    }

    private func metaItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var engineBadgeText: String {
        let config = model.config(for: game)
        return config.d3dMetal ? "D3DMetal" : (config.dxvk ? "DXVK" : (config.dxmt ? "DXMT" : "Default"))
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            if let runningInfo {
                runningBadge(runningInfo)
            } else {
                Button {
                    onLaunch()
                    model.launchSteamGame(game)
                } label: {
                    if model.launchingTarget == .game(game.appID) {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Launching…")
                        }
                    } else {
                        Label("Launch", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.big)
                .disabled(model.launchingTarget != nil)
                .frame(maxWidth: 260)
                .focusRing(isFocused(.launch))
            }
            if isAdvancedMode {
                Button {
                    showingSettings = true
                } label: {
                    Label(hasCustomSettings ? "Custom Settings" : "Settings", systemImage: hasCustomSettings ? "slider.horizontal.3" : "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focusRing(isFocused(.settings))
                .popover(isPresented: $showingSettings) {
                    GameSettingsPopover(game: game)
                }
            }
            Button {
                model.revealInFinder(installFolderPath)
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .focusRing(isFocused(.reveal))
            Button {
                model.openStorePage(for: game)
            } label: {
                Label("Store Page", systemImage: "safari")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .focusRing(isFocused(.storePage))
        }
        .padding(.top, 8)
    }

    private func runningBadge(_ info: RunningProcessInfo) -> some View {
        TimelineView(.periodic(from: info.startedAt, by: 60)) { context in
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Running \(elapsedString(from: info.startedAt, to: context.date))")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func elapsedString(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    private var installFolderPath: String {
        (SteamInstaller.steamBottle.driveCPath as NSString)
            .appendingPathComponent("Program Files (x86)/Steam/steamapps/common")
            .appending("/\(game.installDir)")
    }
}

// MARK: - Dashboard theming

/// A quiet, blurred version of the currently-running game's header art behind the whole dashboard -
/// not the macOS desktop, just this window's own background. Subtler than `LaunchOverlayView`
/// (which is the same idea at full intensity while a game is starting up) so the actual dashboard
/// content on top stays perfectly readable.
private struct DashboardBackdropView: View {
    let game: SteamGame
    @LocalState private var headerImagePath: String?

    var body: some View {
        Group {
            if let headerImagePath, let image = LocalImageCache.image(atPath: headerImagePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 70)
                    .overlay(.background.opacity(0.82))
            } else {
                Color.clear
            }
        }
        .task(id: game.appID) {
            headerImagePath = await SteamStoreInfoCache.shared.info(for: game.metadataAppID)?.headerImagePath
        }
    }
}

// MARK: - Launch overlay

/// The full-window "WHOOSH" launch takeover: the game's own header art fills the screen while it
/// starts. Deliberately not a true `matchedGeometryEffect` hero transition from the exact card that
/// was clicked - `GameCardView` lives inside a `LazyVGrid`/`ScrollView`, where a card that hasn't
/// been scrolled into view yet may not have a measured frame for the effect to animate from, which
/// risks a broken-looking animation for a real but relatively rare case. A scale+fade transition
/// (applied by the caller) gets the same "whoosh" feeling reliably instead.
private struct LaunchOverlayView: View {
    let game: SteamGame
    let config: GameModeConfig
    @LocalState private var headerImagePath: String?

    var body: some View {
        ZStack {
            background
            VStack(spacing: 14) {
                Spacer()
                Text(game.name)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                LoadingDotsView(message: "LAUNCHING…")
                Text(engineSummary)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
            }
        }
        // This overlay's background is always a dark blurred image regardless of system appearance,
        // so force dark-mode semantic colors (.secondary etc. inside LoadingDotsView) rather than
        // risking low-contrast mid-gray text if the system happens to be in light mode.
        .colorScheme(.dark)
        .task {
            headerImagePath = await SteamStoreInfoCache.shared.info(for: game.metadataAppID)?.headerImagePath
        }
    }

    @ViewBuilder
    private var background: some View {
        if let headerImagePath, let image = LocalImageCache.image(atPath: headerImagePath) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 40)
                .overlay(Color.black.opacity(0.55))
        } else {
            LinearGradient(colors: [Color.accentColor.opacity(0.5), .black], startPoint: .top, endPoint: .bottom)
        }
    }

    private var engineSummary: String {
        var parts = [config.engineName ?? "Sikarugir"]
        if config.d3dMetal {
            parts.append("D3DMetal")
        } else if config.dxvk {
            parts.append("DXVK")
        } else if config.dxmt {
            parts.append("DXMT")
        }
        return parts.joined(separator: " • ")
    }
}

// MARK: - Settings

/// The engine/graphics/sync fields shared by both the global "Default Settings" sheet and each
/// game's own settings popover - the exact same controls that used to sit permanently in Game
/// Mode's form, now tucked away for anyone who doesn't need them.
struct GameSettingsFields: View {
    @Binding var config: GameModeConfig

    var body: some View {
        Section("Engine") {
            Picker("Wine engine", selection: $config.engineName) {
                ForEach(SikarugirEngine.availableEngineNames(), id: \.self) { name in
                    Text(name).tag(Optional(name))
                }
            }
            Text("These are the same engines already downloaded by Sikarugir Creator.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Graphics") {
            Toggle("D3DMETAL", isOn: $config.d3dMetal)
            Toggle("MoltenVK CX", isOn: $config.moltenVKCX)
            Toggle("DXVK", isOn: $config.dxvk)
            Toggle("DXMT", isOn: $config.dxmt)
        }

        Section("Sync") {
            Toggle("WINEESYNC", isOn: $config.wineESync)
            Toggle("WINEMSYNC", isOn: $config.wineMSync)
        }
    }
}

/// "Check for Engine Updates" - queries the real `Sikarugir-App/Engines` GitHub release
/// (`SikarugirEnginesRemote`) for the currently-recommended build and compares it against what's
/// already downloaded. Checking is free/instant; the actual (potentially ~160MB) download only
/// happens on an explicit tap.
private struct EngineUpdateSection: View {
    @LocalState private var isChecking = false
    @LocalState private var isDownloading = false
    @LocalState private var updateAvailable: RemoteEngineAsset?
    @LocalState private var statusText: String?

    var body: some View {
        Section {
            if let updateAvailable {
                Text("A newer engine is available: \(updateAvailable.name)")
                    .font(.callout)
                Button {
                    downloadUpdate(updateAvailable)
                } label: {
                    if isDownloading {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Downloading…")
                        }
                    } else {
                        Text("Download Update")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDownloading)
            } else {
                Button {
                    checkForUpdates()
                } label: {
                    if isChecking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Checking…")
                        }
                    } else {
                        Label("Check for Engine Updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isChecking)
            }
            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Engine")
        } footer: {
            Text("Playdock's Wine engine comes from Sikarugir's public releases. Checking never downloads anything by itself.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func checkForUpdates() {
        isChecking = true
        statusText = nil
        Task {
            do {
                let assets = try await SikarugirEnginesRemote.fetchAvailableAssets()
                guard let recommended = SikarugirEnginesRemote.recommendedAsset(among: assets) else {
                    isChecking = false
                    statusText = "No engines found."
                    return
                }
                let alreadyHave = Set(SikarugirEngine.availableEngineNames()).contains(recommended.name)
                isChecking = false
                if alreadyHave {
                    statusText = "You already have the latest recommended engine (\(recommended.name))."
                } else {
                    updateAvailable = recommended
                }
            } catch {
                isChecking = false
                statusText = error.localizedDescription
            }
        }
    }

    private func downloadUpdate(_ asset: RemoteEngineAsset) {
        isDownloading = true
        Task {
            do {
                try await SikarugirEnginesRemote.download(asset) { message in
                    Task { @MainActor in statusText = message }
                }
                isDownloading = false
                updateAvailable = nil
                statusText = "Downloaded \(asset.name) - pick it in Advanced Mode's engine list, or it'll be offered next time a bottle needs (re)initializing."
            } catch {
                isDownloading = false
                statusText = error.localizedDescription
            }
        }
    }
}

/// The top-level rows in `DefaultSettingsSheet` that a controller can navigate directly - the two
/// toggles, the two diagnostics buttons, and Done. `GameSettingsFields`/`EngineUpdateSection`'s own
/// nested controls (sliders, pickers) aren't part of this focus loop yet - a smaller follow-up,
/// same as the header/search/sort scope boundary on the main dashboard.
private enum SettingsRow: Int, CaseIterable {
    case advancedMode, sampleGames, openLogs, openCrashReports, done
}

private struct DefaultSettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var controllerObserver = ControllerObserver.shared
    @Binding var isAdvancedMode: Bool
    @LocalState private var focusedRow: SettingsRow?

    private func isFocused(_ row: SettingsRow) -> Bool {
        controllerObserver.isConnected && focusedRow == row
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Game Mode Settings").font(.title3).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .focusRing(isFocused(.done))
            }
            .padding(16)
            Divider()

            Form {
                Section {
                    Toggle("Advanced Mode", isOn: $isAdvancedMode)
                        .focusRing(isFocused(.advancedMode))
                } footer: {
                    Text("Adds a settings button to each game so you can fine-tune its engine and graphics settings individually. Most people never need this.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isAdvancedMode {
                    GameSettingsFields(config: $model.gameModeConfig)
                }

                EngineUpdateSection()

                Section {
                    Toggle("Preview With Sample Games", isOn: Binding(
                        get: { model.isPreviewingSampleGames },
                        set: { _ in model.togglePreviewSampleGames() }
                    ))
                    .focusRing(isFocused(.sampleGames))
                } footer: {
                    Text("Adds 11 well-known games (real art/ratings, nothing actually installed) so you can see how the grid looks at different sizes. Turn off to remove them - they're never saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        model.revealInFinder(ExeRunner.logsDir)
                    } label: {
                        Label("Open Logs Folder", systemImage: "doc.text.magnifyingglass")
                    }
                    .focusRing(isFocused(.openLogs))
                    Button {
                        model.revealInFinder(("~/Library/Logs/DiagnosticReports" as NSString).expandingTildeInPath)
                    } label: {
                        Label("Open Crash Reports", systemImage: "exclamationmark.triangle")
                    }
                    .focusRing(isFocused(.openCrashReports))
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Every launch writes its own wine log here, plus a running record of background checks (like fetching a game's store art). If something's not working, this is the first place to look.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: controllerObserver.directionPress?.token) { _ in
                guard let direction = controllerObserver.directionPress?.direction, direction == .up || direction == .down else { return }
                let all = SettingsRow.allCases
                guard let current = focusedRow, let index = all.firstIndex(of: current) else {
                    focusedRow = all.first
                    return
                }
                focusedRow = all[safe: direction == .up ? index - 1 : index + 1] ?? current
            }
            .onChange(of: controllerObserver.primaryPress) { _ in
                switch focusedRow {
                case .advancedMode: isAdvancedMode.toggle()
                case .sampleGames: model.togglePreviewSampleGames()
                case .openLogs: model.revealInFinder(ExeRunner.logsDir)
                case .openCrashReports: model.revealInFinder(("~/Library/Logs/DiagnosticReports" as NSString).expandingTildeInPath)
                case .done: dismiss()
                case nil: break
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 420, height: isAdvancedMode ? 660 : 380)
        .animation(.easeInOut(duration: 0.2), value: isAdvancedMode)
    }
}

private struct GameSettingsPopover: View {
    @EnvironmentObject private var model: AppModel
    let game: SteamGame
    @LocalState private var showingExperiment = false

    var body: some View {
        VStack(spacing: 0) {
            Text(game.name)
                .font(.headline)
                .lineLimit(1)
                .padding(14)
            Divider()
            Form {
                FindBestConfigurationSection(itemID: game.appID, itemName: game.name)
                GameSettingsFields(config: configBinding)
                Button("Use Default Settings") {
                    model.setOverride(nil, for: game)
                }
                .disabled(model.perGameConfigs[game.appID] == nil)

                Section {
                    Button {
                        showingExperiment = true
                    } label: {
                        Label("Experiment", systemImage: "flask")
                    }
                } footer: {
                    Text("Try a few engine/graphics combinations one at a time and see which actually works.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                InspectSection(itemID: game.appID, itemName: game.name, installPath: installFolderPath)
            }
            .formStyle(.grouped)
        }
        .frame(width: 380, height: 660)
        .sheet(isPresented: $showingExperiment) {
            ExperimentSheet(game: game)
        }
    }

    private var configBinding: Binding<GameModeConfig> {
        Binding(
            get: { model.perGameConfigs[game.appID] ?? model.gameModeConfig },
            set: { model.setOverride($0, for: game) }
        )
    }

    private var installFolderPath: String {
        (SteamInstaller.steamBottle.driveCPath as NSString)
            .appendingPathComponent("Program Files (x86)/Steam/steamapps/common")
            .appending("/\(game.installDir)")
    }
}

// MARK: - Find Best Configuration

/// "🔎 Find Best Configuration" - pulls public compatibility evidence (AppleGamingWiki, GitHub) plus
/// this Mac's own launch history through `CompatibilityFinder`, and shows the aggregated result.
/// Never applies anything by itself - Apply is always a distinct, explicit tap that goes through the
/// existing `model.setOverride`, the same mechanism the manual settings below already use.
struct FindBestConfigurationSection: View {
    @EnvironmentObject private var model: AppModel
    let itemID: String
    let itemName: String
    @LocalState private var recommendation: CompatibilityRecommendation?
    @LocalState private var isSearching = false
    @LocalState private var showingEvidence = false

    var body: some View {
        Section {
            if isSearching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching AppleGamingWiki, GitHub…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let recommendation {
                resultView(recommendation)
            } else {
                Button {
                    search(forceRefresh: false)
                } label: {
                    Label("Find Best Configuration", systemImage: "magnifyingglass.circle")
                }
            }
        } header: {
            Text("Recommended Settings")
        } footer: {
            Text("Looks at public compatibility reports and this Mac's own launch history for this game. Nothing is ever applied automatically - you choose.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resultView(_ recommendation: CompatibilityRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(recommendation.confidence.indicator) \(recommendation.confidence.label)")
                    .font(.callout).bold()
                Spacer()
                Button {
                    search(forceRefresh: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }

            if recommendation.confidence == .none {
                Text("Nothing was changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Supported by \(independentSourceCount(recommendation)) independent report(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(summary(of: recommendation.recommendedSettings))
                    .font(.callout)
            }

            if !recommendation.reports.isEmpty {
                Button(showingEvidence ? "Hide Evidence" : "View Evidence") {
                    showingEvidence.toggle()
                }
                .buttonStyle(.borderless)
                if showingEvidence {
                    evidenceList(recommendation.reports)
                }
            }

            if recommendation.recommendedSettings != nil {
                Button("Apply") {
                    model.setOverride(recommendation.applied(onto: model.config(forID: itemID)), forID: itemID)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 2)
    }

    private func evidenceList(_ reports: [CompatibilityReport]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(reports) { report in
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.sourceName).font(.caption).bold()
                    Text(report.excerpt).font(.caption2).foregroundStyle(.secondary)
                    if let url = URL(string: report.sourceURL), !report.sourceURL.isEmpty {
                        Link(report.sourceURL, destination: url).font(.caption2)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func independentSourceCount(_ recommendation: CompatibilityRecommendation) -> Int {
        Set(recommendation.reports.map(\.sourceName)).count
    }

    private func summary(of settings: DetectedSettings?) -> String {
        guard let settings else { return "No changes to your current settings." }
        var parts: [String] = []
        if let v = settings.d3dMetal { parts.append("D3DMetal \(v ? "on" : "off")") }
        if let v = settings.dxvk { parts.append("DXVK \(v ? "on" : "off")") }
        if let v = settings.dxmt { parts.append("DXMT \(v ? "on" : "off")") }
        if let v = settings.moltenVKCX { parts.append("MoltenVK CX \(v ? "on" : "off")") }
        if let v = settings.wineESync { parts.append("ESync \(v ? "on" : "off")") }
        if let v = settings.wineMSync { parts.append("MSync \(v ? "on" : "off")") }
        return parts.isEmpty ? "No changes to your current settings." : parts.joined(separator: " · ")
    }

    private func search(forceRefresh: Bool) {
        isSearching = true
        Task {
            let result = await CompatibilityFinder.shared.recommendation(id: itemID, name: itemName, forceRefresh: forceRefresh)
            await MainActor.run {
                recommendation = result
                isSearching = false
            }
        }
    }
}

// MARK: - Inspect

/// "🔬 Inspect" - a read-only assembly of data Playdock already has, plus `RunningGameTracker` for
/// the live PID. No new data sources here, just a presentation layer.
struct InspectSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    let itemID: String
    let itemName: String
    let installPath: String

    private var runningInfo: RunningProcessInfo? { runningTracker.runningGames[itemID] }
    private var config: GameModeConfig { model.config(forID: itemID) }

    var body: some View {
        Section("Inspect") {
            DisclosureGroup("Process") {
                if let runningInfo {
                    LabeledContent("Status", value: "Running (PID \(runningInfo.pid))")
                    LabeledContent("Started", value: runningInfo.startedAt.formatted(date: .omitted, time: .shortened))
                } else {
                    LabeledContent("Status", value: "Not running")
                }
            }
            DisclosureGroup("Wine") {
                LabeledContent("Engine", value: config.engineName ?? "Auto (recommended)")
            }
            DisclosureGroup("Graphics") {
                LabeledContent("D3DMetal", value: config.d3dMetal ? "On" : "Off")
                LabeledContent("DXVK", value: config.dxvk ? "On" : "Off")
                LabeledContent("DXMT", value: config.dxmt ? "On" : "Off")
                LabeledContent("MoltenVK CX", value: config.moltenVKCX ? "On" : "Off")
            }
            DisclosureGroup("Files") {
                Text(installPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button {
                    model.revealInFinder(installPath)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Loading

/// A simple three-dot bounce, the same shape as most chat/loading indicators - used wherever Game
/// Mode has no content shape to show a skeleton of yet (installing Steam itself).
private struct LoadingDotsView: View {
    let message: String
    @LocalState private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 12)
                        .offset(y: isAnimating ? -8 : 0)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(index) * 0.15),
                            value: isAnimating
                        )
                }
            }
            .frame(height: 24)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .onAppear { isAnimating = true }
    }
}

/// A shimmering stand-in for a `GameCardView`, shown in the same grid the real cards land in while
/// the Steam library scan is still running.
private struct GameCardSkeleton: View {
    @LocalState private var isShimmering = false

    private var shimmerColor: Color {
        Color.secondary.opacity(isShimmering ? 0.22 : 0.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(shimmerColor).frame(height: 140)
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4).fill(shimmerColor).frame(width: 150, height: 20)
                RoundedRectangle(cornerRadius: 4).fill(shimmerColor).frame(height: 10)
                RoundedRectangle(cornerRadius: 4).fill(shimmerColor).frame(width: 100, height: 10)
                RoundedRectangle(cornerRadius: 12).fill(shimmerColor).frame(height: 50).padding(.top, 4)
            }
            .padding(16)
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isShimmering = true
            }
        }
    }
}
