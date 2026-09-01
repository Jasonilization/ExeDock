import SwiftUI
import AppKit

/// The games grid's own measured available width, propagated up from the GeometryReader that
/// measures it - see that measurement's own doc comment for why a PreferenceKey rather than a raw
/// `.onChange` on the geometry value.
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
    @AppStorage(LibraryLayoutStyle.storageKey) private var libraryLayoutRaw = LibraryLayoutStyle.grid.rawValue
    private var libraryLayout: LibraryLayoutStyle { LibraryLayoutStyle(rawValue: libraryLayoutRaw) ?? .grid }
    @AppStorage(PlaydockSkin.storageKey) private var skinRaw = PlaydockSkin.luxury.rawValue
    private var skin: PlaydockSkin { PlaydockSkin(rawValue: skinRaw) ?? .luxury }
    @LocalState private var search = ""
    @LocalState private var showingSettingsSheet = false
    @LocalState private var showingAddGameSheet = false
    @LocalState private var sortOption: GameSortOption = .name
    @LocalState private var launchOverlayGame: SteamGame?
    @LocalState private var launchOverlayCustomGame: CustomGame?
    @LocalState private var showingControllerMode = false
    @LocalState private var detailGame: SteamGame?
    @LocalState private var detailCustomGame: CustomGame?
    /// Everywhere a controller's D-pad can currently be focused on the dashboard - the toolbar
    /// (Refresh/Settings), a card in the grid, or the floating Steam icon. `nil` until the first
    /// D-pad press (mouse-only browsing shows no ring at all).
    @LocalState private var focusedTarget: DashboardFocusTarget?
    /// The grid's own measured width - used only for controller D-pad row math (`columnCount`), not
    /// the grid's actual rendering (that's plain `.adaptive`, handled natively by SwiftUI). See
    /// `gridColumns`'s own doc comment for why this split matters.
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
            // The exe's own filename (no extension) rather than its containing folder - a build
            // folder is often something generic like "Win64" or "bin" shared by many different
            // games, while the exe's own name (e.g. "Dreamcore-Win64-Shipping") is virtually always
            // distinctive enough on its own to actually identify the right process.
            + model.customGames.map { (id: $0.id, matchFragment: (($0.exePath as NSString).lastPathComponent as NSString).deletingPathExtension) }
    }

    private var dashboard: some View {
        ZStack {
            SkinBackground(skin: skin)
                .ignoresSafeArea()

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
                // The width measurement comes from a GeometryReader wrapping the ScrollView itself,
                // not from measuring the grid (or any of its scrollable content) directly - two
                // earlier attempts both measured something *downstream* of the grid's own sizing
                // decision instead (the padded container around it, then the grid's own rendered
                // size), and both were self-defeating in the same way: whatever wraps an overflowing
                // child always measures back a value *at least* as large as the overflow itself,
                // hiding the very thing this needed to detect. This GeometryReader instead measures
                // what its own parent (this VStack) actually proposes to it - fixed by the outer
                // layout, never inflated by anything inside it - a true, honest reading of the
                // available space. Propagated back up via the standard PreferenceKey mechanism
                // (`GridWidthKey`), not a raw `.onChange` on the captured `geometry` value, for the
                // same reason: it's the far more standard, battle-tested way to communicate a
                // descendant's measured size back up a SwiftUI view tree. "library cards still
                // overlap," repeated live feedback across several fixes at this same spot.
                if libraryLayout == .grid {
                    GeometryReader { geometry in
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 20) {
                                    searchBar
                                    gamesGrid
                                }
                                .padding(24)
                            }
                            .onChange(of: focusedTarget) { target in
                                guard case .card(let index) = target, libraryEntries.indices.contains(index) else { return }
                                withAnimation { scrollProxy.scrollTo(libraryEntries[index].id, anchor: .center) }
                            }
                        }
                        // 48 = the VStack's own .padding(24) on each side, which sits between this
                        // measurement and the grid it's actually sizing for.
                        .background(
                            Color.clear.preference(key: GridWidthKey.self, value: max(0, geometry.size.width - 48))
                        )
                    }
                    .onPreferenceChange(GridWidthKey.self) { gridWidth = $0 }
                } else {
                    // Every non-grid layout is a genuinely different structure - some own their
                    // own sidebar/scrolling entirely (Sidebar, Steam-style), so they render full-
                    // bleed here rather than being squeezed into the grid's own padded ScrollView
                    // wrapper. "Search actual game design... maybe just dont have cards," per live
                    // feedback - these are real, distinct navigation models, not the grid reskinned.
                    alternateLayout
                }
            }

            steamFloatingIcon
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(24)
                .allowsHitTesting(
                    detailGame == nil && detailCustomGame == nil && launchOverlayGame == nil
                        && launchOverlayCustomGame == nil && !showingControllerMode
                )

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
                } onLaunch: {
                    self.detailCustomGame = nil
                    launchOverlayCustomGame = detailCustomGame
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(1)
            }

            if let launchOverlayGame {
                LaunchOverlayView(game: launchOverlayGame, config: model.config(for: launchOverlayGame))
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(1)
            }

            if let launchOverlayCustomGame {
                CustomLaunchOverlayView(
                    game: launchOverlayCustomGame,
                    statusLine: "Launching via \(model.resolvedBottle(forExePath: launchOverlayCustomGame.exePath).name)…"
                )
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
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: launchOverlayCustomGame?.id)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: detailGame?.appID)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: detailCustomGame?.id)
        .animation(.easeInOut(duration: 0.4), value: themedGame?.appID)
        .animation(.easeInOut(duration: 0.25), value: showingControllerMode)
        .skinned()
        // The real fix for "every skin's cards look like the same generic grey box": without this,
        // system-adaptive colors (`Color.primary`, `.regularMaterial`, default text) silently
        // followed the *system's* Dark Mode setting instead of the skin actually on screen - so a
        // light skin like Brutalist (cream `SkinBackground`, hardcoded RGB) still got a "black"
        // border that resolved to *white* against Dark Mode, invisible on its own light card. Each
        // skin now pins the same light/dark identity its `SkinBackground` was already built for.
        .preferredColorScheme(skin.colorScheme)
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
            if let launchOverlayCustomGame, running[launchOverlayCustomGame.id] != nil {
                self.launchOverlayCustomGame = nil
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
        .onChange(of: launchOverlayCustomGame?.id) { id in
            guard let id else { return }
            Task {
                try? await Task.sleep(for: .seconds(20))
                if launchOverlayCustomGame?.id == id {
                    launchOverlayCustomGame = nil
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
        // A subtle material behind the toolbar row - the top of a real surface stack (toolbar
        // above the grid, grid above the backdrop) instead of sitting flush/transparent against
        // whatever's behind it, so it reads as its own distinct layer even over a themed backdrop.
        .background(.bar)
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
            HStack(spacing: 8) {
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
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Playdock.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Playdock.Radius.control, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )

            Picker("Sort", selection: $sortOption) {
                ForEach(GameSortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .frame(maxWidth: 220)
        }
    }

    /// The card size a few-vs-many-games count alone picks - big, prominent cards for a small
    /// library instead of sitting tiny in a corner of a mostly-empty window; a large library steps
    /// down to a denser grid so more fits per screen.
    private var idealCardSizeTier: (minWidth: CGFloat, maxWidth: CGFloat, artworkHeight: CGFloat) {
        switch libraryEntries.count {
        case 0...2: return (480, 640, 260)
        case 3...6: return (360, 440, 190)
        case 7...15: return (280, 340, 150)
        default: return (240, 280, 130)
        }
    }

    private static let gridSpacing: CGFloat = Playdock.Spacing.grid

    /// The grid's own column layout, back to plain `.adaptive(minimum:maximum:)` - SwiftUI works
    /// out how many columns actually fit *natively*, using the grid's own real proposed width
    /// directly, with no external measurement of any kind needed. A self-computed column count/
    /// width (an earlier version of this) needed `gridWidth` - measured via a GeometryReader
    /// elsewhere in this view - to be correct and current at the moment the grid renders, and in
    /// practice that measurement didn't reliably arrive: confirmed live via a screenshot showing
    /// the grid stuck rendering a single narrow column with a large empty area beside it - the
    /// exact fallback behavior of a stale/zero measurement, not a sizing-math error. `.adaptive`
    /// sidesteps the whole dependency by not needing that value at all. Card *width enforcement*
    /// (`.frame(maxWidth: idealCardSizeTier.maxWidth)` at each call site, below) still fixes the
    /// real, separately-confirmed overlap cause (a card rendering wider than its own column) - with
    /// a real, static ceiling this time, not `.infinity`, after a second screenshot showed genuine
    /// z-index stacking on a *partial* last row, where nothing stopped a card from growing
    /// arbitrarily wide with no upper bound at all.
    private var gridColumns: [GridItem] {
        let tier = idealCardSizeTier
        return [GridItem(.adaptive(minimum: tier.minWidth, maximum: tier.maxWidth), spacing: Self.gridSpacing)]
    }

    /// Best-effort column count for controller D-pad row math only (`moveFocus`) - *not* used for
    /// the grid's own rendering anymore, so an imprecise `gridWidth` measurement here can make
    /// D-pad up/down jump the "wrong" number of cards at worst, never break the actual visual
    /// layout the way it did when this same measurement was load-bearing for column count itself.
    private var columnCount: Int {
        guard gridWidth > 0 else { return 1 }
        let minWidth = idealCardSizeTier.minWidth
        return max(1, Int((gridWidth + Self.gridSpacing) / (minWidth + Self.gridSpacing)))
    }

    private var artworkHeight: CGFloat { idealCardSizeTier.artworkHeight }

    /// Only active while nothing's covering the dashboard (no Game Detail view, no Controller Mode
    /// carousel) - both of those own the same D-pad/A stream the instant they're shown, per
    /// `ControllerObserver`'s "single owner, self-filtering subscribers" design.
    private var isDashboardTheActiveControllerLayer: Bool {
        detailGame == nil && detailCustomGame == nil && !showingControllerMode
    }

    /// Real 2D movement across every focusable spot on the dashboard: the toolbar row above the
    /// grid, the grid itself (up/down jump a full row via `columnCount`, left/right stop at row
    /// edges instead of wrapping into the row above/below), and the floating Steam icon beyond the
    /// grid's last row.
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
            let columns = columnCount
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
            LazyVGrid(columns: gridColumns, spacing: Self.gridSpacing) {
                ForEach(0..<6, id: \.self) { _ in GameCardSkeleton().frame(maxWidth: idealCardSizeTier.maxWidth) }
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
            LazyVGrid(columns: gridColumns, spacing: Self.gridSpacing) {
                ForEach(Array(libraryEntries.enumerated()), id: \.element.id) { index, entry in
                    let isFocused = controllerObserver.isConnected && focusedTarget == .card(index)
                    switch entry {
                    case .steam(let game):
                        GameCardView(
                            game: game, isAdvancedMode: isAdvancedMode, artworkHeight: artworkHeight,
                            isFocused: isFocused
                        ) {
                            launchOverlayGame = game
                        } onOpenDetail: {
                            detailGame = game
                        }
                        // Explicit, not left to the grid cell alone: real evidence (a screenshot)
                        // showed each card's *artwork* bleeding edge-to-edge into its neighbor with
                        // zero visible gap, while the text/button area below it was genuinely
                        // spaced apart correctly - a `GridItem(.adaptive(...))` column apparently
                        // only governs *positioning*, not an enforced content-width ceiling, so a
                        // card with no width ceiling of its own can render wider than its column and
                        // overlap the next one. `maxWidth: .infinity` (an earlier version of this
                        // fix) turned out to have no real ceiling at all - fine for a full row, but
                        // a real, second, separately-confirmed overlap (this time genuine z-index
                        // stacking, via another screenshot) showed up specifically on a *partial*
                        // last row, where nothing was left to stop a card from growing arbitrarily
                        // wide. `idealCardSizeTier.maxWidth` is a real, static ceiling - not tied to
                        // any measurement - matching the exact same maximum `.adaptive` itself
                        // already uses for this same tier, so it can never disagree with the grid's
                        // own column math.
                        .frame(maxWidth: idealCardSizeTier.maxWidth)
                    case .custom(let customGame):
                        CustomGameCardView(
                            game: customGame, isAdvancedMode: isAdvancedMode, artworkHeight: artworkHeight,
                            isFocused: isFocused
                        ) {
                            launchOverlayCustomGame = customGame
                        } onOpenDetail: {
                            detailCustomGame = customGame
                        }
                        .frame(maxWidth: idealCardSizeTier.maxWidth)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.steamGames)
            .animation(.easeInOut(duration: 0.2), value: model.customGames)
            // Deliberately NOT animated on column size - `LazyVGrid` doesn't reflow smoothly when
            // its own column count/width changes, and this grid's own sizing changes often (every
            // resize, every count-driven tier change), so an implicit animation on it means near-
            // constant transitions with real potential to visibly overlap mid-flight.
        }
    }

    /// Routes to whichever real, structurally distinct layout is picked in Settings - all of them
    /// share the same `libraryEntries` (so search/sort still apply) and the same "open detail" path
    /// the grid's own cards already use, so the actual game data, launch flow, and detail view are
    /// identical no matter which structure is on screen; only how entries are arranged differs.
    @ViewBuilder
    private var alternateLayout: some View {
        let openDetail: (LibraryEntry) -> Void = { entry in
            switch entry {
            case .steam(let game): detailGame = game
            case .custom(let game): detailCustomGame = game
            }
        }
        switch libraryLayout {
        case .grid: EmptyView() // unreachable - handled above
        case .shelves: LibraryShelvesLayout(entries: libraryEntries, onOpenDetail: openDetail)
        case .sidebar: LibrarySidebarLayout(entries: libraryEntries, onOpenDetail: openDetail)
        case .list: LibraryListLayout(entries: libraryEntries, onOpenDetail: openDetail)
        case .steam: LibrarySteamStyleLayout(entries: libraryEntries, onOpenDetail: openDetail)
        case .carousel: LibraryCarouselLayout(entries: libraryEntries, onOpenDetail: openDetail)
        case .launchpad: LibraryLaunchpadLayout(entries: libraryEntries, onOpenDetail: openDetail)
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
    @LocalState private var isHoveringCard = false

    private var hasCustomSettings: Bool { model.perGameConfigs[game.appID] != nil }
    private var runningInfo: RunningProcessInfo? { runningTracker.runningGames[game.appID] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 4) {
                    SkinTitleText(text: game.name, size: 20)
                        .help(developerHelpText)
                    Spacer()
                    if isAdvancedMode && game.source == .wineBottle {
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
                if runningInfo != nil {
                    RunningBadge()
                } else {
                    openDetailHint
                }
            }
            .padding(20)
        }
        .cardSurface(isHovering: isHoveringCard)
        .focusRing(isFocused)
        // Tapping the card opens the full Game Detail view rather than launching straight away -
        // "it should go into full screen before you can launch," per live feedback, so the grid
        // card itself is just an entry point now. A plain single-tap gesture on this container is
        // safe alongside the gearshape Button above (SwiftUI routes a tap within a nested Button's
        // own bounds to that button first) - this is a different situation from the earlier
        // Steam-tile bug, which was specifically a *simultaneous* zero-distance DragGesture
        // competing with a double-tap recognizer on the very same view.
        .contentShape(RoundedRectangle(cornerRadius: Playdock.Radius.card))
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
                // The real Steam appid, not ExeDock's own internally-namespaced `appID` (which can
                // carry a "MAC-"/"SAMPLE-" prefix so it never collides with a same-appid entry from
                // a different source) - copying that prefix out to a user would be actively wrong.
                NSPasteboard.general.setString(game.metadataAppID, forType: .string)
            } label: {
                Label("Copy App ID", systemImage: "doc.on.doc")
            }
        }
        .task(id: game.appID) {
            storeInfo = await SteamStoreInfoCache.shared.info(for: game.metadataAppID)
        }
        .onHover { isHovering in
            isHoveringCard = isHovering
            if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var installFolderPath: String { game.installFolderPath }

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
            if game.source == .wineBottle {
                Text(engineBadgeText)
            } else {
                Text("Mac")
            }
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
    /// Non-nil while a photo is shown full-size over everything else - "images are expandable for
    /// the more detail pictures," per live feedback.
    @LocalState private var expandedImagePath: String?

    private var runningInfo: RunningProcessInfo? { runningTracker.runningGames[game.appID] }
    private var hasCustomSettings: Bool { model.perGameConfigs[game.appID] != nil }

    /// Exactly the same conditions `actionRow` already uses to decide what to show - kept as one
    /// list so controller focus always lines up with what's actually on screen (e.g. never
    /// highlights a Settings button that isn't rendered outside Advanced Mode).
    private var availableActions: [DetailAction] {
        var actions: [DetailAction] = []
        if runningInfo == nil { actions.append(.launch) }
        // A native macOS Steam game has no ExeDock-managed wine bottle/engine to configure.
        if isAdvancedMode && game.source == .wineBottle { actions.append(.settings) }
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
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        // Photos sit in their own column to the right of the text, not stacked
                        // below it - "pictures should be at the RIGHT," per live feedback.
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 22) {
                                actionRow
                                descriptionCard
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if hasPhotos {
                                photoGrid
                            }
                        }
                    }
                    .padding(32)
                    // The double .frame() is deliberate, not redundant: the first caps the content
                    // column's own width so it stays readable at 1320pt; the second then re-expands
                    // that capped block to fill whatever width the ScrollView actually has and
                    // re-applies leading alignment *within* that full width. A single
                    // `.frame(maxWidth: 1320, alignment: .leading)` only caps the view's own size -
                    // it doesn't reliably left-anchor it against a wider ancestor, which is exactly
                    // what put this content off-screen entirely: confirmed live, content rendering
                    // well past the left edge of the window with no way to reach the close button.
                    .frame(maxWidth: 1320, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let expandedImagePath {
                imageLightbox(expandedImagePath)
                    .transition(.opacity)
                    .zIndex(10)
            }
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
            guard expandedImagePath == nil, let direction = controllerObserver.directionPress?.direction else { return }
            moveActionFocus(direction)
        }
        .onChange(of: controllerObserver.primaryPress) { _ in
            guard expandedImagePath == nil else { return }
            activateFocusedAction()
        }
        .onChange(of: controllerObserver.secondaryPress) { _ in
            // Back out one level at a time - close the expanded photo first if one's open, the
            // whole detail view otherwise.
            if expandedImagePath != nil {
                expandedImagePath = nil
            } else {
                onClose()
            }
        }
    }

    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                // A real solid backing, not just the SF Symbol's own faint built-in shadow layer -
                // busy, high-contrast game art (bright whites, bold text baked into the artwork
                // itself) can wash the old icon-only close button out almost completely. "Stuck" in
                // a detail view with no visible way out, per live feedback.
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25)))
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
            SkinTitleText(text: game.name, size: 34)
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

    /// The full "About This Game" copy, styled as its own card rather than plain running text -
    /// "make it better looking with the description," per live feedback. Falls back to the short
    /// description for anything fetched before this field existed, or with no fuller write-up.
    @ViewBuilder
    private var descriptionCard: some View {
        if let description = storeInfo?.aboutTheGame ?? storeInfo?.shortDescription {
            VStack(alignment: .leading, spacing: 10) {
                Text("About This Game")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(description)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
        }
    }

    /// Header art first, then every screenshot, in that order - the one list both `hasPhotos` and
    /// `photoGrid` build rows from.
    private var allPhotoPaths: [String] {
        var paths: [String] = []
        if let headerImagePath = storeInfo?.headerImagePath { paths.append(headerImagePath) }
        paths.append(contentsOf: storeInfo?.screenshotPaths ?? [])
        return paths
    }

    /// True whenever there's actually something to put in `photoGrid`.
    private var hasPhotos: Bool { !allPhotoPaths.isEmpty }

    /// A fixed-width column of photos to the right of the text - "pictures should be at the
    /// RIGHT," per live feedback, after a prior full-width row layout still didn't land right.
    /// Two thumbnails per row (rather than one) so it's still "rows... without scrolling" rather
    /// than one long single-file column - sized up twice now per repeated "make the media pictures
    /// bigger" feedback, with the content column widened to match so the text side doesn't get
    /// squeezed. Each thumbnail gets both its width *and* height fixed in one `.frame()` call
    /// before `.fill` crops it, so every photo renders at exactly the same size no matter its own
    /// screenshot's native aspect ratio. Tap one to open the *complete*, uncropped image via
    /// `imageLightbox` - "images are expandable for the more detail pictures."
    private var photoGrid: some View {
        let rows = allPhotoPaths.chunked(into: 2)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Media")
                .font(.headline)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 20) {
                ForEach(rows.indices, id: \.self) { rowIndex in
                    HStack(spacing: 20) {
                        ForEach(rows[rowIndex], id: \.self) { path in
                            photoThumbnail(path)
                        }
                    }
                }
            }
        }
        .frame(width: 560, alignment: .leading)
    }

    private func photoThumbnail(_ path: String) -> some View {
        Group {
            if let image = LocalImageCache.image(atPath: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 270, height: 155)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { expandedImagePath = path }
            }
        }
    }

    /// A full-size, uncropped look at one photo - tap anywhere (or press Escape/B) to dismiss.
    private func imageLightbox(_ path: String) -> some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            if let image = LocalImageCache.image(atPath: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(60)
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        expandedImagePath = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .padding(24)
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { expandedImagePath = nil }
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


    private var actionRow: some View {
        HStack(spacing: 12) {
            if runningInfo != nil {
                RunningBadge(compact: true)
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
            if isAdvancedMode && game.source == .wineBottle {
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

    private var installFolderPath: String { game.installFolderPath }
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
/// (applied by the caller) gets the same "whoosh" feeling reliably instead. Custom games get the
/// exact same treatment via `CustomLaunchOverlayView` below - previously they got nothing at all,
/// so clicking Launch looked like it silently did nothing: "boot any game it should have the
/// booting screen and also where it's at. for gamers thye just see the screen and think it didn't
/// work," per live feedback.
private struct LaunchOverlayView: View {
    let game: SteamGame
    let config: GameModeConfig
    @LocalState private var headerImagePath: String?

    var body: some View {
        LaunchOverlayContent(name: game.name, artworkPath: headerImagePath, statusLine: engineSummary)
            .task {
                headerImagePath = await SteamStoreInfoCache.shared.info(for: game.metadataAppID)?.headerImagePath
            }
    }

    /// A native macOS Steam game runs through the real Steam app directly - no Wine, no engine, no
    /// D3D backend involved at all, so showing one here would be actively wrong, not just unused
    /// chrome - "the thing saying d3dmetal on mac steam games is a bit misleading," per live
    /// feedback. Empty (not shown) rather than some other placeholder text.
    private var engineSummary: String {
        guard game.source == .wineBottle else { return "" }
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

/// The same launch takeover for a custom game - no async metadata fetch needed, since its artwork
/// path is already sitting right on the model. `statusLine` names where it's actually launching
/// *from* (Playdock itself, or a specific Sikarugir wrapper app when the launch was delegated to
/// one) instead of an engine/D3D summary, which wouldn't mean anything to a player either way -
/// "also...where it's at," per live feedback.
private struct CustomLaunchOverlayView: View {
    let game: CustomGame
    let statusLine: String

    var body: some View {
        LaunchOverlayContent(name: game.effectiveName, artworkPath: game.effectiveArtworkPath, statusLine: statusLine)
    }
}

private struct LaunchOverlayContent: View {
    let name: String
    let artworkPath: String?
    let statusLine: String

    var body: some View {
        ZStack {
            background
            VStack(spacing: 14) {
                Spacer()
                Text(name)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                LoadingDotsView(message: "LAUNCHING…")
                if !statusLine.isEmpty {
                    Text(statusLine)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
            }
        }
        // This overlay's background is always a dark blurred image regardless of system appearance,
        // so force dark-mode semantic colors (.secondary etc. inside LoadingDotsView) rather than
        // risking low-contrast mid-gray text if the system happens to be in light mode.
        .colorScheme(.dark)
    }

    @ViewBuilder
    private var background: some View {
        if let artworkPath, let image = LocalImageCache.image(atPath: artworkPath) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 40)
                .overlay(Color.black.opacity(0.55))
        } else {
            LinearGradient(colors: [Color.accentColor.opacity(0.5), .black], startPoint: .top, endPoint: .bottom)
        }
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
            Toggle("Fast Sync (ESYNC + MSYNC)", isOn: $config.fastSync)
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
    @AppStorage(LibraryLayoutStyle.storageKey) private var libraryLayoutRaw = LibraryLayoutStyle.grid.rawValue
    @AppStorage(PlaydockSkin.storageKey) private var skinRaw = PlaydockSkin.luxury.rawValue

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

                Section {
                    Picker("Layout", selection: $libraryLayoutRaw) {
                        ForEach(LibraryLayoutStyle.allCases) { style in
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                    Picker("Appearance", selection: $skinRaw) {
                        ForEach(PlaydockSkin.allCases) { skin in
                            Text(skin.displayName).tag(skin.rawValue)
                        }
                    }
                } header: {
                    Text("Library Look")
                } footer: {
                    Text((LibraryLayoutStyle(rawValue: libraryLayoutRaw) ?? .grid).subtitle)
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
        .frame(width: 420, height: isAdvancedMode ? 680 : 460)
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

    private var installFolderPath: String { game.installFolderPath }
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
        .cardSurface()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isShimmering = true
            }
        }
    }
}
