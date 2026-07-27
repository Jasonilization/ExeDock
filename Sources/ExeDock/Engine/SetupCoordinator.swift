import Foundation
import AppKit

enum SetupStage: Equatable {
    case checking
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

    private func performSetup() async {
        stage = .checking

        // Already fully set up, or just needs its cheap cached path? (Runs off the main thread
        // since this can shell out to `tar` the first time.)
        if await engineIsAvailable() {
            await ensureDefaultBottleReady()
            return
        }

        // Sikarugir already downloaded an engine tarball - extracting it is a local copy, no
        // network involved, so ExeDock can just do this for you.
        if SikarugirEngine.hasDownloadedTarball() {
            stage = .extractingEngine
            if await engineIsAvailable() {
                await ensureDefaultBottleReady()
            } else {
                stage = .failed("Found a Sikarugir engine but couldn't prepare it. Try relaunching ExeDock.")
            }
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
                stage = .extractingEngine
                if await engineIsAvailable() {
                    await ensureDefaultBottleReady()
                } else {
                    stage = .failed("Found a Sikarugir engine but couldn't prepare it. Try relaunching ExeDock.")
                }
                return
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    private func ensureDefaultBottleReady() async {
        stage = .initializingBottle
        let bottle = BottleManager.shared.defaultBottle
        do {
            try await Task.detached(priority: .userInitiated) {
                let wine = try SikarugirEngine.wineBinaryPath()
                try BottleManager.shared.ensureInitialized(bottle, wineBinary: wine)
            }.value
            stage = .ready
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    /// Offloads the (possibly slow, shells-out-to-`tar`) engine resolution off the main thread.
    private func engineIsAvailable() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            SikarugirEngine.isEngineAvailable()
        }.value
    }
}
