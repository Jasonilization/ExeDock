import Foundation
import AppKit

enum SetupStage: Equatable {
    case checking
    /// More than one engine is downloaded and none is extracted yet - genuinely ambiguous, so
    /// setup pauses here for the user to pick (see `SetupCoordinator.chooseEngine(_:)`) instead of
    /// silently guessing. `recommended` is pre-highlighted in the UI.
    case choosingEngine(options: [String], recommended: String?)
    case extractingEngine
    case initializingBottle
    case waitingForSikarugirCreator
    case missingSikarugirCreator
    case ready
    case failed(String)
}

/// Runs automatically at launch: makes sure a Sikarugir engine and ExeDock's own bottle are ready
/// to go before the main UI appears, "installing" whatever's missing using only what's already
/// legitimately on this Mac.
///
/// ExeDock never fabricates its own download URL for a Wine engine - if nothing is available yet,
/// the only safe move is to hand off to Sikarugir Creator (the app that owns that download) and
/// wait for it, rather than guessing at a binary to fetch and run.
@MainActor
final class SetupCoordinator: ObservableObject {
    static let sikarugirCreatorPath = "/Applications/Sikarugir Creator.app"

    @Published var stage: SetupStage = .checking

    private var pollTask: Task<Void, Never>?

    func runSetup() {
        pollTask?.cancel()
        pollTask = Task { await performSetup() }
    }

    /// Called from the setup screen when more than one engine was offered and the user picked one.
    func chooseEngine(_ name: String) {
        pollTask?.cancel()
        pollTask = Task { await extractAndContinue(engineName: name) }
    }

    private func performSetup() async {
        stage = .checking

        // A cheap, side-effect-free check - safe to do first no matter how many engines are
        // downloaded, since it never triggers an extraction the user hasn't chosen yet.
        if SikarugirEngine.hasReadyCachedEngine() {
            await ensureDefaultBottleReady()
            return
        }

        // Sikarugir already downloaded at least one engine tarball - extracting it is a local copy,
        // no network involved, so ExeDock can just do this for you. If it downloaded more than one,
        // that's a real choice worth asking about rather than silently guessing.
        if SikarugirEngine.hasDownloadedTarball() {
            let names = SikarugirEngine.availableEngineNames()
            if names.count > 1 {
                stage = .choosingEngine(options: names, recommended: SikarugirEngine.recommendedEngineName())
                return
            }
            await extractAndContinue(engineName: names.first)
            return
        }

        // Nothing to extract yet. If Sikarugir Creator is installed, let IT fetch an engine - ExeDock
        // won't guess at a download URL of its own for a Wine build.
        guard FileManager.default.fileExists(atPath: Self.sikarugirCreatorPath) else {
            stage = .missingSikarugirCreator
            return
        }

        stage = .waitingForSikarugirCreator
        NSWorkspace.shared.open(URL(fileURLWithPath: Self.sikarugirCreatorPath))
        await pollForEngine()
    }

    private func pollForEngine() async {
        while !Task.isCancelled {
            if SikarugirEngine.hasDownloadedTarball() {
                let names = SikarugirEngine.availableEngineNames()
                if names.count > 1 {
                    stage = .choosingEngine(options: names, recommended: SikarugirEngine.recommendedEngineName())
                } else {
                    await extractAndContinue(engineName: names.first)
                }
                return
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    private func extractAndContinue(engineName: String?) async {
        stage = .extractingEngine
        let resolved = await Task.detached(priority: .userInitiated) {
            try? SikarugirEngine.wineBinaryPath(engineName: engineName)
        }.value
        guard resolved != nil else {
            stage = .failed("Found a Sikarugir engine but couldn't prepare it. Try relaunching ExeDock.")
            return
        }
        // Pass the same name along so the bottle is initialized with the exact engine that was
        // just extracted, not whatever `wineBinaryPath()` would pick again on its own.
        await ensureDefaultBottleReady(engineName: engineName)
    }

    private func ensureDefaultBottleReady(engineName: String? = nil) async {
        stage = .initializingBottle
        let bottle = BottleManager.shared.defaultBottle
        do {
            try await Task.detached(priority: .userInitiated) {
                let wine = try SikarugirEngine.wineBinaryPath(engineName: engineName)
                try BottleManager.shared.ensureInitialized(bottle, wineBinary: wine)
            }.value
            stage = .ready
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }
}
