import SwiftUI

/// "🔬 Experiment" - tries a fixed ladder of engine/graphics variants for one game, **manually
/// paced**: the player launches exactly one variant at a time and Launch is disabled until that
/// attempt resolves. This is deliberate, not an oversight - an earlier version of Playdock had an
/// automatic launch-retry ladder that was removed after it raced against Steam's own singleton
/// hand-off and launched a second, competing Steam process (confirmed in
/// ~/Library/Logs/ExeDock at the time). An auto-chaining Experiment feature would reintroduce
/// exactly that risk, so this never launches anything without an explicit tap.
///
/// Each result - auto-detected via `RunningGameTracker`, or corrected by hand if the game started
/// but wasn't actually playable - is written to `LocalOutcomeTracker`, so Experiment results
/// directly strengthen future "Find Best Configuration" recommendations for this game.
struct ExperimentSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    let game: SteamGame

    @LocalState private var results: [String: Bool] = [:]
    @LocalState private var testingVariantID: String?

    private struct Variant: Identifiable {
        let id: String
        let label: String
        let config: GameModeConfig
    }

    private var variants: [Variant] {
        let base = model.config(for: game)

        var d3dMetal = base
        d3dMetal.d3dMetal = true; d3dMetal.dxvk = false; d3dMetal.dxmt = false

        var dxvk = base
        dxvk.d3dMetal = false; dxvk.dxvk = true; dxvk.dxmt = false

        var dxmt = base
        dxmt.d3dMetal = false; dxmt.dxvk = false; dxmt.dxmt = true

        var d3dMetalESync = d3dMetal
        d3dMetalESync.wineESync = true

        var dxvkESync = dxvk
        dxvkESync.wineESync = true

        return [
            Variant(id: "baseline", label: "Baseline (your saved settings)", config: base),
            Variant(id: "d3dmetal", label: "D3DMetal", config: d3dMetal),
            Variant(id: "dxvk", label: "DXVK", config: dxvk),
            Variant(id: "dxmt", label: "DXMT", config: dxmt),
            Variant(id: "d3dmetal-esync", label: "D3DMetal + ESync", config: d3dMetalESync),
            Variant(id: "dxvk-esync", label: "DXVK + ESync", config: dxvkESync),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Experiment: \(game.name)").font(.title3).bold()
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(16)
            Divider()

            Form {
                Section {
                    ForEach(variants) { variant in
                        variantRow(variant)
                    }
                } header: {
                    Text("Try each one, one at a time")
                } footer: {
                    Text("Launches never chain automatically. Launch a variant, actually try playing it, then mark or Launch the next.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let best = bestVariant {
                    Section("So Far") {
                        Label("Best: \(best.label)", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 440, height: 560)
        .onChange(of: runningTracker.runningGames) { running in
            guard let testingVariantID, running[game.appID] != nil else { return }
            recordResult(true, for: testingVariantID)
        }
    }

    private var bestVariant: Variant? {
        variants.first { results[$0.id] == true }
    }

    private func variantRow(_ variant: Variant) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(variant.label)
                if let result = results[variant.id] {
                    Text(result ? "Marked working" : "Marked not working")
                        .font(.caption2)
                        .foregroundStyle(result ? .green : .red)
                }
            }
            Spacer()

            if testingVariantID == variant.id {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    recordResult(true, for: variant.id)
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Mark as working")

                Button {
                    recordResult(false, for: variant.id)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Mark as not working")

                Button("Launch") {
                    launch(variant)
                }
                .buttonStyle(.bordered)
                .disabled(testingVariantID != nil || model.launchingTarget != nil)
            }
        }
    }

    private func launch(_ variant: Variant) {
        testingVariantID = variant.id
        model.launchSteamGame(game, using: variant.config)

        Task {
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                if runningTracker.runningGames[game.appID] != nil {
                    recordResult(true, for: variant.id)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
            // No process seen within the grace period - auto-mark as failed to start. The user can
            // still correct this by hand if it actually did start under a name the tracker missed.
            if testingVariantID == variant.id {
                recordResult(false, for: variant.id)
            }
        }
    }

    private func recordResult(_ worked: Bool, for variantID: String) {
        guard let variant = variants.first(where: { $0.id == variantID }) else { return }
        results[variantID] = worked
        if testingVariantID == variantID { testingVariantID = nil }
        LocalOutcomeTracker.record(appID: game.appID, config: variant.config, launchErrored: !worked)
    }
}
