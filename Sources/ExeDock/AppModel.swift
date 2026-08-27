import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    enum SidebarSection: Hashable {
        case gameMode
        case library
        case cDrive
    }

    enum SteamStatus: Equatable {
        case notInstalled
        case installing(String)
        case installed
        case failed(String)
    }

    @Published var detectedApps: [DetectedApp] = []
    @Published var bottles: [Bottle] = []
    // Steam-first: gamers land straight on the dashboard, not a generic file browser.
    @Published var selectedSection: SidebarSection = .gameMode
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var steamStatus: SteamStatus = .notInstalled
    // didSet (not a separate save call) so every mutation persists automatically, including direct
    // bindings from the settings UI ($model.gameModeConfig.dxvk, etc.) - not just `setOverride`.
    @Published var gameModeConfig = GameModeConfig() { didSet { persistGameSettings() } }
    @Published var perGameConfigs: [String: GameModeConfig] = [:] { didSet { persistGameSettings() } }
    @Published var isGameModeUnlocked = false
    @Published var steamGames: [SteamGame] = []
    @Published var isLoadingSteamGames = false
    @Published var steamProfile: SteamProfile?

    var isInstallingSteam: Bool {
        if case .installing = steamStatus { return true }
        return false
    }

    // Deliberately does nothing but set defaults above. Mutating @Published properties from inside
    // an ObservableObject's own init() (which SwiftUI can invoke mid-render for a @StateObject) is a
    // known trigger for "Publishing changes from within view updates is not allowed" - real symptoms
    // observed here included whole panes of the UI going blank. All initial loading instead happens
    // in `onSetupReady()`, called from an `.onChange`/`.onAppear`, safely outside any view's body.
    init() {}

    /// Called once launch-time setup finishes (see `SetupCoordinator`) - safe to publish freely here.
    func onSetupReady() {
        isGameModeUnlocked = SteamInstaller.isSteamInstalled
        if isGameModeUnlocked { steamStatus = .installed }
        let saved = GameSettingsStore.load()
        gameModeConfig = saved.defaults
        perGameConfigs = saved.perGame
        refreshBottlesAndApps()
        refreshSteamGames()
        refreshSteamProfile()
    }

    func refreshBottlesAndApps() {
        let knownBottles = CDriveScanner.allKnownBottles()
        bottles = knownBottles
        detectedApps = knownBottles.flatMap(CDriveScanner.scan)
    }

    func refreshSteamGames() {
        guard isGameModeUnlocked else {
            steamGames = []
            return
        }
        isLoadingSteamGames = true
        Task.detached(priority: .utility) { [weak self] in
            let games = SteamLibrary.installedGames()
            await MainActor.run { [weak self] in
                self?.steamGames = games
                self?.isLoadingSteamGames = false
            }
        }
    }

    func refreshSteamProfile() {
        guard isGameModeUnlocked else {
            steamProfile = nil
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            let profile = SteamProfileReader.currentProfile()
            await MainActor.run { [weak self] in self?.steamProfile = profile }
        }
    }

    /// Settings that actually apply to `game` - its own override if it has one, otherwise the
    /// shared default. Advanced Mode is the only place a user can create an override.
    func config(for game: SteamGame) -> GameModeConfig {
        perGameConfigs[game.appID] ?? gameModeConfig
    }

    func setOverride(_ config: GameModeConfig?, for game: SteamGame) {
        perGameConfigs[game.appID] = config
    }

    private func persistGameSettings() {
        GameSettingsStore.save(defaults: gameModeConfig, perGame: perGameConfigs)
    }

    func run(exePath: String, bottle: Bottle, arguments: [String] = [], displayName: String? = nil) {
        let isSteamBottle = isGameModeUnlocked && bottle.id == SteamInstaller.steamBottle.id
        let env = isSteamBottle ? gameModeConfig.environment : [:]
        let engineName = isSteamBottle ? gameModeConfig.engineName : nil
        let name = displayName ?? (exePath as NSString).lastPathComponent
        statusMessage = "Launching \(name)…"
        // A bottle that isn't initialized yet can take a while (wineboot + a grace period for its
        // background helper processes to finish) - never do that on the main thread.
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try ExeRunner.run(exePath: exePath, in: bottle, arguments: arguments, extraEnvironment: env, engineName: engineName)
                await MainActor.run { [weak self] in self?.statusMessage = "Launched \(name)" }
            } catch {
                await MainActor.run { [weak self] in self?.errorMessage = error.localizedDescription }
            }
        }
    }

    /// Games are always started through Steam itself (`-applaunch <appid>`) rather than by running
    /// their executable directly - see `SteamGame.iconExePath` for why. Uses that game's own
    /// settings override if it has one (see `GameLauncher`), retrying with fallback settings if the
    /// first attempt fails fast.
    func launchSteamGame(_ game: SteamGame) {
        launchWithFallback(
            exePath: SteamInstaller.installedSteamExePath,
            bottle: SteamInstaller.steamBottle,
            arguments: ["-applaunch", game.appID],
            displayName: game.name,
            baseConfig: config(for: game)
        )
    }

    /// Opens the Steam client itself (no specific game) - e.g. to browse the store or install
    /// something new. Also goes through the fallback ladder, since this is the same call that has
    /// to succeed before any per-game launch can.
    func openSteamClient() {
        launchWithFallback(
            exePath: SteamInstaller.installedSteamExePath,
            bottle: SteamInstaller.steamBottle,
            arguments: [],
            displayName: "Steam",
            baseConfig: gameModeConfig
        )
    }

    private func launchWithFallback(exePath: String, bottle: Bottle, arguments: [String], displayName: String, baseConfig: GameModeConfig) {
        let attempts = GameLauncher.ladder(from: baseConfig)
        statusMessage = "Launching \(displayName)…"
        Task.detached(priority: .userInitiated) { [weak self] in
            for (index, attempt) in attempts.enumerated() {
                let isLast = index == attempts.count - 1
                do {
                    let process = try ExeRunner.run(
                        exePath: exePath, in: bottle, arguments: arguments,
                        extraEnvironment: attempt.config.environment, engineName: attempt.config.engineName
                    )
                    if await !GameLauncher.failedQuickly(process) {
                        await MainActor.run { [weak self] in self?.statusMessage = "Launched \(displayName)" }
                        return
                    }
                } catch {
                    if isLast {
                        await MainActor.run { [weak self] in self?.errorMessage = error.localizedDescription }
                        return
                    }
                }
                if !isLast {
                    let nextLabel = attempts[index + 1].label
                    await MainActor.run { [weak self] in
                        self?.statusMessage = "\(displayName) didn't start - trying \(nextLabel)…"
                    }
                }
            }
            await MainActor.run { [weak self] in
                self?.errorMessage = "\(displayName) didn't start after trying a few different settings. Check ~/Library/Logs/ExeDock, or fine-tune its settings in Advanced Mode."
            }
        }
    }

    func runDroppedFile(at path: String) {
        guard path.lowercased().hasSuffix(".exe") else {
            errorMessage = "ExeDock only runs .exe files."
            return
        }
        run(exePath: path, bottle: BottleManager.shared.defaultBottle)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.refreshBottlesAndApps()
        }
    }

    func installAndRunSteam() {
        guard !isInstallingSteam else { return }
        steamStatus = .installing("Starting…")
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await SteamInstaller.installAndLaunch { [self] message in
                    Task { @MainActor in self.steamStatus = .installing(message) }
                }
                self.steamStatus = .installed
                self.isGameModeUnlocked = true
                self.selectedSection = .gameMode
                self.openSteamClient()
                self.refreshBottlesAndApps()
                self.refreshSteamGames()
                self.refreshSteamProfile()
            } catch {
                self.steamStatus = .failed(error.localizedDescription)
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
