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
                }
            }
            .formStyle(.grouped)
        }
    }

    private var engineSelection: Binding<String?> {
        Binding(
            get: { model.gameModeConfig.engineName },
            set: { model.gameModeConfig.engineName = $0 }
        )
    }
}
