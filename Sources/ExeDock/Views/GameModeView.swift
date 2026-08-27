import SwiftUI
import AppKit

struct GameModeView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("com.exedock.advancedMode") private var isAdvancedMode = false
    @LocalState private var search = ""
    @LocalState private var showingSettingsSheet = false

    private var filteredGames: [SteamGame] {
        search.isEmpty ? model.steamGames : model.steamGames.filter { $0.name.localizedCaseInsensitiveContains(search) }
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
        VStack(spacing: 20) {
            if model.isInstallingSteam {
                GameModeLoadingView(message: installingMessage)
            } else {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Your games live here once Steam is installed.")
                    .font(.title3)
                Button("Install & Run Steam") {
                    model.installAndRunSteam()
                }
                .buttonStyle(.borderedProminent)
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
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    searchBar
                    gamesGrid
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $showingSettingsSheet) {
            DefaultSettingsSheet(isAdvancedMode: $isAdvancedMode)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            profileAvatar
            VStack(alignment: .leading, spacing: 2) {
                Text(model.steamProfile?.personaName ?? "Steam")
                    .font(.title2).bold()
                Text(model.steamGames.isEmpty ? "No games installed yet" : "\(model.steamGames.count) game\(model.steamGames.count == 1 ? "" : "s") installed")
                    .font(.callout)
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
            .disabled(model.isLoadingSteamGames)

            Button {
                showingSettingsSheet = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)

            Button("Open Steam") {
                model.openSteamClient()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
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
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search your games", text: $search)
                .textFieldStyle(.plain)
                .font(.title3)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var gamesGrid: some View {
        if model.isLoadingSteamGames && model.steamGames.isEmpty {
            GameModeLoadingView(message: "Looking for installed games…")
        } else if model.steamGames.isEmpty {
            emptyGamesState
        } else if filteredGames.isEmpty {
            Text("No games match \u{201C}\(search)\u{201D}.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 18)], spacing: 18) {
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 4) {
                    Text(game.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if isAdvancedMode {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: hasCustomSettings ? "slider.horizontal.3" : "gearshape")
                        }
                        .buttonStyle(.borderless)
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
                Button("Launch") {
                    model.launchSteamGame(game)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
            .padding(12)
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .task(id: game.appID) {
            storeInfo = await SteamStoreInfoCache.shared.info(for: game.appID)
        }
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
                Image(nsImage: AppIconProvider.icon(forPath: game.iconExePath ?? SteamInstaller.installedSteamExePath))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.15))
            }
        }
        .frame(height: 100)
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
            }
            .formStyle(.grouped)
        }
        .frame(width: 420, height: isAdvancedMode ? 520 : 220)
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

/// A game-themed loading indicator for Game Mode: a controller icon that gently pulses inside a
/// spinning progress ring, used both while ExeDock installs Steam and while it scans the Steam
/// bottle for installed games - a plain spinner felt out of place in a section all about games.
private struct GameModeLoadingView: View {
    let message: String
    @LocalState private var isAnimating = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.15), lineWidth: 6)
                    .frame(width: 72, height: 72)
                Circle()
                    .trim(from: 0, to: 0.26)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: isAnimating)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(isAnimating ? 1.1 : 0.9)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isAnimating)
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .onAppear { isAnimating = true }
    }
}
