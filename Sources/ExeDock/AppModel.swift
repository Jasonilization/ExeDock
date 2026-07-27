import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    enum SidebarSection: Hashable {
        case library
        case cDrive
        case gameMode
        case about
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

    var isInstallingSteam: Bool {
        if case .installing = steamStatus { return true }
        return false
    }

    init() {
        isGameModeUnlocked = SteamInstaller.isSteamInstalled
        if isGameModeUnlocked { steamStatus = .installed }
        refreshBottlesAndApps()
    }

    func refreshBottlesAndApps() {
        let knownBottles = CDriveScanner.allKnownBottles()
        bottles = knownBottles
        detectedApps = knownBottles.flatMap(CDriveScanner.scan)
    }

    func run(exePath: String, bottle: Bottle) {
        do {
            let env = (isGameModeUnlocked && bottle.id == SteamInstaller.steamBottle.id) ? gameModeConfig.environment : [:]
            try ExeRunner.run(exePath: exePath, in: bottle, extraEnvironment: env)
            statusMessage = "Launched \((exePath as NSString).lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
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
                let exePath = try await SteamInstaller.installAndLaunch { [self] message in
                    Task { @MainActor in self.steamStatus = .installing(message) }
                }
                self.steamStatus = .installed
                self.isGameModeUnlocked = true
                self.selectedSection = .gameMode
                self.run(exePath: exePath, bottle: SteamInstaller.steamBottle)
                self.refreshBottlesAndApps()
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
}
