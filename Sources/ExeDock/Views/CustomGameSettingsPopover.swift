import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Mirrors `GameSettingsPopover`'s structure, reusing the generalized `FindBestConfigurationSection`/
/// `GameSettingsFields`/`InspectSection` directly rather than copying their logic - the whole point
/// of generalizing those off a plain id/name earlier. No Experiment section here: `ExperimentSheet`
/// is built specifically around comparing settings through a real Steam launch
/// (`AppModel.launchSteamGame(_:using:)`), which doesn't have a clean custom-game equivalent - a
/// reasonable, disclosed scope trim rather than force-fitting it.
struct CustomGameSettingsPopover: View {
    @EnvironmentObject private var model: AppModel
    let game: CustomGame

    var body: some View {
        VStack(spacing: 0) {
            Text(game.effectiveName)
                .font(.headline)
                .lineLimit(1)
                .padding(14)
            Divider()
            Form {
                FindBestConfigurationSection(itemID: game.id, itemName: game.effectiveName)
                GameSettingsFields(config: configBinding)
                Button("Use Default Settings") {
                    model.setOverride(nil, forID: game.id)
                }
                .disabled(model.perGameConfigs[game.id] == nil)

                InspectSection(itemID: game.id, itemName: game.effectiveName, installPath: (game.exePath as NSString).deletingLastPathComponent)
            }
            .formStyle(.grouped)
        }
        .frame(width: 380, height: 560)
    }

    private var configBinding: Binding<GameModeConfig> {
        Binding(
            get: { model.perGameConfigs[game.id] ?? model.gameModeConfig },
            set: { model.setOverride($0, forID: game.id) }
        )
    }
}

/// Name/description/launch-argument overrides, plus the ability to point at a different executable
/// if the game moved - all written into `CustomGame.overrides` via `AppModel.updateCustomGame`.
/// Never touches `discovered` (the auto-found metadata) so re-editing never loses what was found
/// automatically; clearing a field back to empty here just means "use the discovered value again."
struct EditCustomGameSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let game: CustomGame

    @LocalState private var name: String
    @LocalState private var description: String
    @LocalState private var launchArguments: String

    init(game: CustomGame) {
        self.game = game
        _name = LocalState(wrappedValue: game.overrides.name ?? "")
        _description = LocalState(wrappedValue: game.overrides.description ?? "")
        _launchArguments = LocalState(wrappedValue: game.launchArguments.joined(separator: " "))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Game").font(.title3).bold()
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            Divider()

            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text(game.discovered.productName ?? CustomGame.cleanedName(fromExePath: game.exePath)))
                } header: {
                    Text("Name")
                } footer: {
                    Text("Leave blank to use the automatically discovered name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Description") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    TextField("e.g. -windowed -skipintro", text: $launchArguments)
                } header: {
                    Text("Launch Arguments")
                }

                Section {
                    Text(game.exePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button {
                        chooseExecutable()
                    } label: {
                        Label("Change Executable…", systemImage: "doc.badge.gearshape")
                    }
                } header: {
                    Text("Executable")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 440, height: 480)
    }

    private func save() {
        var updated = game
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.overrides.name = trimmedName.isEmpty ? nil : trimmedName
        updated.overrides.description = trimmedDescription.isEmpty ? nil : trimmedDescription
        let args = launchArguments.split(separator: " ").map(String.init)
        updated.overrides.launchArguments = args.isEmpty ? nil : args
        model.updateCustomGame(updated)
        dismiss()
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        if let exeType = UTType(filenameExtension: "exe") { panel.allowedContentTypes = [exeType] }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var updated = game
        updated.exePath = url.path
        model.updateCustomGame(updated)
        dismiss()
    }
}
