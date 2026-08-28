import SwiftUI
import GameController

/// A big, controller-navigable carousel: one game centered at a time, D-pad left/right to switch,
/// A to launch, B to exit back to the normal dashboard. Grabs whichever controller is connected
/// when this view appears - doesn't try to handle a controller swap mid-session, a reasonable v1
/// scope for what's already a fairly involved feature set.
struct ControllerModeView: View {
    @EnvironmentObject private var model: AppModel
    let onExit: () -> Void
    @LocalState private var selectedIndex = 0
    @LocalState private var storeInfo: SteamStoreInfo?

    private var games: [SteamGame] { model.steamGames }
    private var currentGame: SteamGame? { games.indices.contains(selectedIndex) ? games[selectedIndex] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let currentGame {
                VStack(spacing: 20) {
                    Spacer()
                    artwork
                        .frame(width: 280, height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    Text(currentGame.name)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("[ PLAY ]") {
                        model.launchSteamGame(currentGame)
                    }
                    .buttonStyle(.big)
                    .frame(maxWidth: 260)
                    Spacer()
                    neighborRow
                        .padding(.bottom, 32)
                }
            } else {
                Text("No games installed yet")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
            }

            VStack {
                HStack {
                    Spacer()
                    Button("Exit (B)") { onExit() }
                        .buttonStyle(.bordered)
                        .padding(20)
                }
                Spacer()
            }
        }
        .colorScheme(.dark)
        .task(id: currentGame?.appID) {
            guard let currentGame else { return }
            storeInfo = await SteamStoreInfoCache.shared.info(for: currentGame.appID)
        }
        .onAppear { attachControllerHandlers() }
        .onDisappear { detachControllerHandlers() }
    }

    @ViewBuilder
    private var artwork: some View {
        if let path = storeInfo?.headerImagePath, let image = LocalImageCache.image(atPath: path) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else if let currentGame {
            Image(nsImage: AppIconProvider.icon(forPath: currentGame.iconExePath ?? SteamInstaller.installedSteamExePath))
                .resizable().aspectRatio(contentMode: .fit).padding(40)
                .background(Color.accentColor.opacity(0.2))
        }
    }

    private var neighborRow: some View {
        HStack {
            if selectedIndex > 0 {
                Text("← \(games[selectedIndex - 1].name)")
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if selectedIndex < games.count - 1 {
                Text("\(games[selectedIndex + 1].name) →")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .font(.callout)
        .padding(.horizontal, 60)
    }

    private func movePrevious() {
        guard selectedIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) { selectedIndex -= 1 }
    }

    private func moveNext() {
        guard selectedIndex < games.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) { selectedIndex += 1 }
    }

    /// `pressedChangedHandler` (button-edge semantics: fires once per press/release), not
    /// `valueChangedHandler` (fires continuously while held) - the latter would fire dozens of
    /// times a second while the D-pad is held, jumping through the whole list instantly.
    private func attachControllerHandlers() {
        guard let gamepad = GCController.controllers().first?.extendedGamepad else { return }
        gamepad.dpad.left.pressedChangedHandler = { [self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in movePrevious() }
        }
        gamepad.dpad.right.pressedChangedHandler = { [self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in moveNext() }
        }
        gamepad.buttonA.pressedChangedHandler = { [self] _, _, pressed in
            guard pressed, let currentGame else { return }
            Task { @MainActor in model.launchSteamGame(currentGame) }
        }
        gamepad.buttonB.pressedChangedHandler = { [self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in onExit() }
        }
    }

    private func detachControllerHandlers() {
        guard let gamepad = GCController.controllers().first?.extendedGamepad else { return }
        gamepad.dpad.left.pressedChangedHandler = nil
        gamepad.dpad.right.pressedChangedHandler = nil
        gamepad.buttonA.pressedChangedHandler = nil
        gamepad.buttonB.pressedChangedHandler = nil
    }
}
