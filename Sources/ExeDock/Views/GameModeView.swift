import SwiftUI
import AppKit

struct GameModeView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("com.exedock.advancedMode") private var isAdvancedMode = false
    @LocalState private var search = ""
    @LocalState private var showingSettingsSheet = false
    @LocalState private var sortOption: GameSortOption = .name

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

    private var dashboard: some View {
        VStack(spacing: 0) {
            header
            steamLaunchTile
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    searchBar
                    gamesGrid
                }
                .padding(24)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.launchingTarget)
        .sheet(isPresented: $showingSettingsSheet) {
            DefaultSettingsSheet(isAdvancedMode: $isAdvancedMode)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            profileAvatar
            VStack(alignment: .leading, spacing: 2) {
                Text(model.steamProfile?.personaName ?? "Steam")
                    .font(.title).bold()
                Text(model.steamGames.isEmpty ? "No games installed yet" : "\(model.steamGames.count) game\(model.steamGames.count == 1 ? "" : "s") installed")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.refreshSteamGames()
                model.refreshSteamProfile()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isLoadingSteamGames)

            Button {
                showingSettingsSheet = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
        }
        .padding(22)
    }

    /// The big, hard-to-miss way to open Steam itself - double-click, the same gesture as opening
    /// anything else on a Mac. Uses Steam's own real icon when the native Mac Steam.app is present
    /// on this machine (legitimately already installed by the user, same as how AppIconProvider
    /// reads any other already-installed app's icon) - falling back to an in-house glyph otherwise,
    /// since NSWorkspace can't extract an icon from a .exe buried in a private, never-Finder-indexed
    /// Wine bottle. Shows exactly one spinner, right on the icon, while launching.
    private static let nativeSteamAppPath = "/Applications/Steam.app"

    private var steamLaunchTile: some View {
        let isLaunching = model.launchingTarget == .steam
        return VStack(spacing: 10) {
            ZStack {
                steamIcon
                    .opacity(isLaunching ? 0.3 : 1)
                if isLaunching {
                    ProgressView().controlSize(.large)
                }
            }
            .frame(width: 160, height: 160)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 30))
            .hoverSpin()
            .onTapGesture(count: 2) {
                model.openSteamClient()
            }
            .allowsHitTesting(model.launchingTarget == nil)
            Text(isLaunching ? "Launching Steam…" : "Double-click to open Steam")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var steamIcon: some View {
        if FileManager.default.fileExists(atPath: Self.nativeSteamAppPath) {
            Image(nsImage: AppIconProvider.icon(forPath: Self.nativeSteamAppPath))
                .resizable()
                .frame(width: 160, height: 160)
        } else {
            RoundedRectangle(cornerRadius: 30)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.53, green: 0.33, blue: 0.96), Color(red: 0.16, green: 0.18, blue: 0.52)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 64, weight: .medium))
                        .foregroundStyle(.white)
                )
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(0.15), lineWidth: 1))
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
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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

    private let gridColumns = [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 20)]

    @ViewBuilder
    private var gamesGrid: some View {
        if model.isLoadingSteamGames && model.steamGames.isEmpty {
            // Shimmering placeholders in the exact grid the real cards will land in - reads as a
            // proper dashboard loading in, not just "something, somewhere, is thinking."
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(0..<6, id: \.self) { _ in GameCardSkeleton() }
            }
        } else if model.steamGames.isEmpty {
            emptyGamesState
        } else if filteredGames.isEmpty {
            Text("No games match \u{201C}\(search)\u{201D}.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(filteredGames) { game in
                    GameCardView(game: game, isAdvancedMode: isAdvancedMode)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.steamGames)
        }
    }

    private var emptyGamesState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No games installed yet")
                .font(.title3).bold()
            Text("Install something from the Steam store and it'll show up here.")
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
    let game: SteamGame
    let isAdvancedMode: Bool
    @LocalState private var storeInfo: SteamStoreInfo?
    @LocalState private var showingSettings = false

    private var hasCustomSettings: Bool { model.perGameConfigs[game.appID] != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 4) {
                    Text(game.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if isAdvancedMode {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: hasCustomSettings ? "slider.horizontal.3" : "gearshape")
                        }
                        .buttonStyle(.bordered)
                        .clipShape(Circle())
                        .help(hasCustomSettings ? "Custom settings" : "Game settings")
                        .popover(isPresented: $showingSettings) {
                            GameSettingsPopover(game: game)
                        }
                    }
                }
                if let description = storeInfo?.shortDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                detailsRow
                Button {
                    model.launchSteamGame(game)
                } label: {
                    if model.launchingTarget == .game(game.appID) {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Launching…")
                        }
                    } else {
                        Text("Launch")
                    }
                }
                .buttonStyle(.big)
                .disabled(model.launchingTarget != nil)
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .contextMenu {
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
            storeInfo = await SteamStoreInfoCache.shared.info(for: game.appID)
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
            if let size = game.sizeOnDisk {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            if let build = game.buildID {
                Text("Build \(build)")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private var artwork: some View {
        Group {
            if let headerPath = storeInfo?.headerImagePath, let image = LocalImageCache.image(atPath: headerPath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Not a real exe-icon lookup on purpose - NSWorkspace can't extract one from a file
                // buried in a private, never-Finder-indexed Wine bottle, so it just renders blank.
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.15))
            }
        }
        .frame(height: 140)
        .clipped()
    }
}

// MARK: - Settings

/// The engine/graphics/sync fields shared by both the global "Default Settings" sheet and each
/// game's own settings popover - the exact same controls that used to sit permanently in Game
/// Mode's form, now tucked away for anyone who doesn't need them.
private struct GameSettingsFields: View {
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

private struct DefaultSettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var isAdvancedMode: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Game Mode Settings").font(.title3).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            Divider()

            Form {
                Section {
                    Toggle("Advanced Mode", isOn: $isAdvancedMode)
                } footer: {
                    Text("Adds a settings button to each game so you can fine-tune its engine and graphics settings individually. Most people never need this.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isAdvancedMode {
                    GameSettingsFields(config: $model.gameModeConfig)
                }

                Section {
                    Button {
                        model.revealInFinder(ExeRunner.logsDir)
                    } label: {
                        Label("Open Logs Folder", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        model.revealInFinder(("~/Library/Logs/DiagnosticReports" as NSString).expandingTildeInPath)
                    } label: {
                        Label("Open Crash Reports", systemImage: "exclamationmark.triangle")
                    }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Every launch writes its own wine log here, plus a running record of background checks (like fetching a game's store art). If something's not working, this is the first place to look.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 420, height: isAdvancedMode ? 620 : 340)
        .animation(.easeInOut(duration: 0.2), value: isAdvancedMode)
    }
}

private struct GameSettingsPopover: View {
    @EnvironmentObject private var model: AppModel
    let game: SteamGame

    var body: some View {
        VStack(spacing: 0) {
            Text(game.name)
                .font(.headline)
                .lineLimit(1)
                .padding(14)
            Divider()
            Form {
                GameSettingsFields(config: configBinding)
                Button("Use Default Settings") {
                    model.setOverride(nil, for: game)
                }
                .disabled(model.perGameConfigs[game.appID] == nil)
            }
            .formStyle(.grouped)
        }
        .frame(width: 340, height: 460)
    }

    private var configBinding: Binding<GameModeConfig> {
        Binding(
            get: { model.perGameConfigs[game.appID] ?? model.gameModeConfig },
            set: { model.setOverride($0, for: game) }
        )
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
