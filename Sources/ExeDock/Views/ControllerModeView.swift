import SwiftUI
import GameController

/// A big, controller-navigable carousel: one game centered at a time, D-pad left/right to switch, A
/// to drill into that game's full Game Detail view (not launch straight away - "controller mode
/// should just be able to select everything," per live feedback), B to back out one level at a
/// time (out of the detail view first, then out of Controller Mode itself). Grabs whichever
/// controller is connected when this view appears - doesn't try to handle a controller swap
/// mid-session, a reasonable v1 scope for what's already a fairly involved feature set.
struct ControllerModeView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("com.exedock.advancedMode") private var isAdvancedMode = false
    let onExit: () -> Void
    @LocalState private var selectedIndex = 0
    @LocalState private var storeInfo: SteamStoreInfo?
    @LocalState private var showingDetail = false

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
                    if let subtitle = storeInfoSubtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Button("[ SELECT ]") {
                        openDetail()
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
                    Button("Exit (B)") { backOut() }
                        .buttonStyle(.bordered)
                        .padding(20)
                }
                Spacer()
            }

            if showingDetail, let currentGame {
                GameDetailView(game: currentGame, isAdvancedMode: isAdvancedMode) {
                    closeDetail()
                } onLaunch: {
                    model.launchSteamGame(currentGame)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(1)
            }
        }
        .colorScheme(.dark)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showingDetail)
        .task(id: currentGame?.appID) {
            guard let currentGame else { return }
            storeInfo = await SteamStoreInfoCache.shared.info(for: currentGame.metadataAppID)
        }
        .onAppear { attachControllerHandlers() }
        .onDisappear { detachControllerHandlers() }
    }

    private func openDetail() {
        guard currentGame != nil else { return }
        showingDetail = true
    }

    private func closeDetail() {
        showingDetail = false
    }

    /// One controller-style "back" step at a time: out of the detail view first if it's open,
    /// otherwise out of Controller Mode entirely - never both at once from a single B press.
    private func backOut() {
        if showingDetail {
            closeDetail()
        } else {
            onExit()
        }
    }

    private var storeInfoSubtitle: String? {
        guard let storeInfo else { return nil }
        var parts: [String] = []
        if let genre = storeInfo.genres.first { parts.append(genre) }
        if let score = storeInfo.metacriticScore { parts.append("Metacritic \(score)") }
        if let developer = storeInfo.developers.first { parts.append(developer) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
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
        // Left/right only browse the carousel while the detail view isn't covering it - otherwise
        // an accidental D-pad nudge while reading a game's details would swap the game underneath.
        gamepad.dpad.left.pressedChangedHandler = { [self] _, _, pressed in
            guard pressed, !showingDetail else { return }
            Task { @MainActor in movePrevious() }
        }
        gamepad.dpad.right.pressedChangedHandler = { [self] _, _, pressed in
            guard pressed, !showingDetail else { return }
            Task { @MainActor in moveNext() }
        }
        // A drills into the detail view first; only launches once that detail view is already
        // open - the same two-step "select, then confirm" flow a console dashboard uses.
        gamepad.buttonA.pressedChangedHandler = { [self] _, _, pressed in
            guard pressed, let currentGame else { return }
            Task { @MainActor in
                if showingDetail {
                    model.launchSteamGame(currentGame)
                } else {
                    openDetail()
                }
            }
        }
        gamepad.buttonB.pressedChangedHandler = { [self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in backOut() }
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
