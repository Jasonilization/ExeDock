import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    enum SidebarSection: Hashable, CaseIterable {
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

    /// What (if anything) is currently being launched - tracked per-target rather than one blanket
    /// flag so only the control someone actually clicked shows a spinner, not every game card at once.
    enum LaunchTarget: Equatable {
        case steam
        case game(String)
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
    /// Non-nil while a Steam/game launch is in flight - drives the spinner on whichever control
    /// started it, and blocks a second launch from starting until this clears (see `launchSteam`).
    @Published var launchingTarget: LaunchTarget?
    /// Debug-only: appends a handful of real, well-known games (with real appIDs, so their genuine
    /// Steam art/rating/description come through the normal metadata pipeline) so the grid's layout
    /// - especially the dynamic card sizing - can be checked with more than whatever's actually
    /// installed. Purely additive to `steamGames`; never written to disk, never touches the real
    /// Steam library, and toggling it off removes every sample entry immediately.
    @Published private(set) var isPreviewingSampleGames = false

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
    /// settings override if it has one.
    func launchSteamGame(_ game: SteamGame) {
        launchSteamGame(game, using: config(for: game))
    }

    /// Same launch, but with a specific config rather than the game's saved override - used by the
    /// Experiment wizard to try a variant without touching the player's actual saved settings.
    func launchSteamGame(_ game: SteamGame, using config: GameModeConfig) {
        guard ensureSteamStillInstalled() else { return }
        launchSteam(
            target: .game(game.appID), arguments: ["-applaunch", game.appID], displayName: game.name,
            config: config, recordOutcomeFor: game.appID
        )
    }

    /// Opens the Steam client itself (no specific game) - e.g. to browse the store or install
    /// something new.
    func openSteamClient() {
        guard ensureSteamStillInstalled() else { return }
        launchSteam(target: .steam, arguments: [], displayName: "Steam", config: gameModeConfig)
    }

    /// Steam can vanish out from under ExeDock (uninstalled, a broken update) without anything else
    /// noticing, since nothing polls for it while the app just sits open. Re-check right before
    /// trying to launch it, and if it's gone, flip back to the locked state and kick off a reinstall
    /// automatically - `SteamInstaller.installAndLaunch` already knows to skip the download step if
    /// it turns out Steam actually is there after all.
    @discardableResult
    private func ensureSteamStillInstalled() -> Bool {
        guard SteamInstaller.isSteamInstalled else {
            isGameModeUnlocked = false
            steamStatus = .notInstalled
            errorMessage = "Steam isn't where ExeDock expected it anymore - reinstalling…"
            installAndRunSteam()
            return false
        }
        return true
    }

    /// A single, fire-and-forget launch - deliberately NOT retried. Steam.exe's own singleton
    /// behavior means a second invocation while Steam is already running (or still starting up) just
    /// messages the existing process and exits quickly, often with a non-zero status - that's normal,
    /// not a failure, and retrying with different settings on that signal previously caused ExeDock
    /// to launch a second, competing Steam process on top of a first one that was still legitimately
    /// starting up (confirmed in ~/Library/Logs/ExeDock: two full Steam startups five seconds apart).
    /// The `guard` below is a second line of defense against that - it ignores a launch request while
    /// one is already in flight, on top of the UI disabling launch buttons for the same reason.
    private func launchSteam(target: LaunchTarget, arguments: [String], displayName: String, config: GameModeConfig, recordOutcomeFor appID: String? = nil) {
        guard launchingTarget == nil else { return }
        launchingTarget = target
        statusMessage = "Launching \(displayName)…"
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try ExeRunner.run(
                    exePath: SteamInstaller.installedSteamExePath, in: SteamInstaller.steamBottle,
                    arguments: arguments, extraEnvironment: config.environment, engineName: config.engineName
                )
                await MainActor.run { [weak self] in self?.statusMessage = "Launched \(displayName)" }
                if let appID { LocalOutcomeTracker.record(appID: appID, config: config, launchErrored: false) }
            } catch {
                await MainActor.run { [weak self] in self?.errorMessage = error.localizedDescription }
                if let appID { LocalOutcomeTracker.record(appID: appID, config: config, launchErrored: true) }
            }
            // Steam's own window can take a while to appear even after the process starts (first
            // launch, or a self-update - real startups seen taking 10+ seconds) - keep the "in
            // progress" indicator up for a bit so it doesn't flash by before anyone notices it.
            try? await Task.sleep(for: .seconds(6))
            await MainActor.run { [weak self] in self?.launchingTarget = nil }
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

    func openStorePage(for game: SteamGame) {
        guard let url = URL(string: "https://store.steampowered.com/app/\(game.metadataAppID)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Sample games (debug preview)

    /// Real, well-known appIDs on purpose - so their genuine Steam art/rating/genre/description come
    /// straight through the same `SteamStoreInfoCache` pipeline every real card uses, instead of a
    /// hand-faked placeholder that wouldn't actually exercise (or look like) the real thing.
    private static let sampleGameAppIDs: [(appID: String, name: String)] = [
        ("367520", "Hollow Knight"), ("413150", "Stardew Valley"), ("504230", "Celeste"),
        ("1145360", "Hades"), ("620", "Portal 2"), ("220", "Half-Life 2"),
        ("105600", "Terraria"), ("268910", "Cuphead"), ("588650", "Dead Cells"),
        ("632470", "Disco Elysium"), ("753640", "Outer Wilds"),
    ]

    private static var sampleGames: [SteamGame] {
        sampleGameAppIDs.enumerated().map { index, entry in
            SteamGame(
                appID: "SAMPLE-\(entry.appID)", name: entry.name, installDir: entry.name,
                iconExePath: nil, sizeOnDisk: Int64(300_000_000 * (index + 1)),
                buildID: "sample", lastUpdated: Date()
            )
        }
    }

    func togglePreviewSampleGames() {
        isPreviewingSampleGames.toggle()
        if isPreviewingSampleGames {
            steamGames.append(contentsOf: Self.sampleGames)
        } else {
            steamGames.removeAll { $0.appID.hasPrefix("SAMPLE-") }
        }
    }
}
