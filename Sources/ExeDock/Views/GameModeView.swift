import SwiftUI

struct GameModeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if !model.isGameModeUnlocked {
            VStack(spacing: 12) {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Game Mode unlocks once Steam is installed.")
                Button("Install & Run Steam") {
                    model.installAndRunSteam()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isInstallingSteam)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section {
                    if model.isLoadingSteamGames && model.steamGames.isEmpty {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Looking for installed games…").foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    } else if model.steamGames.isEmpty {
                        Text("No installed games found yet. Install something from Steam, then refresh.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    } else {
                        ForEach(model.steamGames) { game in
                            SteamGameRow(game: game)
                                .fadeInOnAppear()
                        }
                    }
                } header: {
                    HStack {
                        Text("Your Steam Games")
                        Spacer()
                        Button {
                            model.refreshSteamGames()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isLoadingSteamGames)
                    }
                }

                Section("Engine") {
                    Picker("Wine engine", selection: engineSelection) {
                        ForEach(SikarugirEngine.availableEngineNames(), id: \.self) { name in
                            Text(name).tag(Optional(name))
                        }
                    }
                    Text("These are the same engines already downloaded by Sikarugir Creator.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Graphics") {
                    Toggle("D3DMETAL", isOn: $model.gameModeConfig.d3dMetal)
                    Toggle("MoltenVK CX", isOn: $model.gameModeConfig.moltenVKCX)
                    Toggle("DXVK", isOn: $model.gameModeConfig.dxvk)
                    Toggle("DXMT", isOn: $model.gameModeConfig.dxmt)
                }

                Section("Sync") {
                    Toggle("WINEESYNC", isOn: $model.gameModeConfig.wineESync)
                    Toggle("WINEMSYNC", isOn: $model.gameModeConfig.wineMSync)
                }

                Section {
                    Button("Launch Steam") {
                        model.run(exePath: SteamInstaller.installedSteamExePath, bottle: SteamInstaller.steamBottle)
                    }
                    .disabled(model.isSteamSessionRunning)

                    if model.isSteamSessionRunning {
                        Button("Force Quit Steam", role: .destructive) {
                            model.forceQuit(bottle: SteamInstaller.steamBottle, displayName: "Steam")
                        }
                        Text("If a game is stuck launching, use this instead of Force Quitting ExeDock - it shuts the whole Wine session down cleanly instead of leaving background processes running.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: model.isSteamSessionRunning)
            }
            .formStyle(.grouped)
            .animation(.easeInOut(duration: 0.25), value: model.isLoadingSteamGames)
            .animation(.easeInOut(duration: 0.25), value: model.steamGames)
        }
    }

    private var engineSelection: Binding<String?> {
        Binding(
            get: { model.gameModeConfig.engineName },
            set: { model.gameModeConfig.engineName = $0 }
        )
    }
}

private struct SteamGameRow: View {
    @EnvironmentObject private var model: AppModel
    let game: SteamGame

    var body: some View {
        HStack {
            Image(nsImage: AppIconProvider.icon(forPath: game.iconExePath ?? SteamInstaller.installedSteamExePath))
                .resizable()
                .frame(width: 28, height: 28)
                .fadeInOnAppear()
            Text(game.name)
            Spacer()
            Button("Launch") {
                model.launchSteamGame(game)
            }
        }
        .padding(.vertical, 2)
    }
}
