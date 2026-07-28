import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    enum SidebarSection: Hashable {
        case library
        case cDrive
        case gameMode
    }

    enum SteamStatus: Equatable {
        case notInstalled
        case installing(String)
        case installed
        case failed(String)
    }

    @Published var detectedApps: [DetectedApp] = []
    @Published var bottles: [Bottle] = []
    @Published var selectedSection: SidebarSection = .library
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var steamStatus: SteamStatus = .notInstalled
    @Published var gameModeConfig = GameModeConfig()
    @Published var isGameModeUnlocked = false
    @Published var steamGames: [SteamGame] = []
    @Published var isLoadingSteamGames = false
    @Published var runningBottleIDs: Set<String> = []

    var isInstallingSteam: Bool {
        if case .installing = steamStatus { return true }
        return false
    }

    var isSteamSessionRunning: Bool {
        runningBottleIDs.contains(SteamInstaller.steamBottle.id)
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
        refreshBottlesAndApps()
        refreshSteamGames()
        // Best-effort cleanup of Wine helper processes stranded by a past hard-kill (Force Quit,
        // a killed hung game, a crash) - see WineProcessReaper for why this is safe to do
        // automatically. Off the main thread since it shells out to `ps`.
        Task.detached(priority: .utility) { WineProcessReaper.sweepOrphans() }
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

    func run(exePath: String, bottle: Bottle, arguments: [String] = [], displayName: String? = nil) {
        let env = (isGameModeUnlocked && bottle.id == SteamInstaller.steamBottle.id) ? gameModeConfig.environment : [:]
        let name = displayName ?? (exePath as NSString).lastPathComponent
        statusMessage = "Launching \(name)…"
        let launchedAt = Date()
        // A bottle that isn't initialized yet can take a while (wineboot + a grace period for its
        // background helper processes to finish) - never do that on the main thread.
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try ExeRunner.run(exePath: exePath, in: bottle, arguments: arguments, extraEnvironment: env) { exitCode in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.runningBottleIDs.remove(bottle.id)
                        // A near-instant exit almost always means it failed to start rather than that
                        // the user already quit it - say so instead of leaving a stale "Launched" status.
                        if exitCode != 0 && Date().timeIntervalSince(launchedAt) < 5 {
                            self.errorMessage = "\(name) quit right after launching (exit code \(exitCode)). Check the newest log in ~/Library/Logs/ExeDock for details."
                        }
                    }
                }
                await MainActor.run { [weak self] in
                    self?.statusMessage = "Launched \(name)"
                    self?.runningBottleIDs.insert(bottle.id)
                }
            } catch {
                await MainActor.run { [weak self] in self?.errorMessage = error.localizedDescription }
            }
        }
    }

    /// Cleanly stops everything running in a bottle's Wine session - the recovery path for a launch
    /// that's hung, offered instead of Force Quitting ExeDock or killing wine from Activity Monitor
    /// (both leave orphaned helper processes behind, see WineProcessReaper).
    func forceQuit(bottle: Bottle, displayName: String) {
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try ExeRunner.forceQuit(bottle: bottle)
                await MainActor.run { [weak self] in
                    self?.runningBottleIDs.remove(bottle.id)
                    self?.statusMessage = "Stopped \(displayName)."
                }
            } catch {
                await MainActor.run { [weak self] in self?.errorMessage = error.localizedDescription }
            }
        }
    }

    /// Games are always started through Steam itself (`-applaunch <appid>`) rather than by running
    /// their executable directly - see `SteamGame.iconExePath` for why.
    func launchSteamGame(_ game: SteamGame) {
        run(
            exePath: SteamInstaller.installedSteamExePath,
            bottle: SteamInstaller.steamBottle,
            arguments: ["-applaunch", game.appID],
            displayName: game.name
        )
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
                let exePath = try await SteamInstaller.installAndLaunch { [self] message in
                    Task { @MainActor in self.steamStatus = .installing(message) }
                }
                self.steamStatus = .installed
                self.isGameModeUnlocked = true
                self.selectedSection = .gameMode
                self.run(exePath: exePath, bottle: SteamInstaller.steamBottle)
                self.refreshBottlesAndApps()
                self.refreshSteamGames()
            } catch {
                self.steamStatus = .failed(error.localizedDescription)
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openSikarugirCreator() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Sikarugir Creator.app"))
    }

    func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/Jasonilization/ExeDock")!)
    }
}
