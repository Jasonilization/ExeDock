import SwiftUI
import AppKit

private enum CustomDetailAction: Equatable {
    case launch, settings, reveal, edit
}

/// The custom-game equivalent of `GameDetailView` - "custom game needs everything a steam game has
/// too," per live feedback. Same visual language (backdrop, header art, rating/genre tags,
/// description, screenshot strip, a controller-navigable action row) but its own type rather than a
/// generalized shared view, since the two diverge in real ways (no Steam store page to link to,
/// an Edit action instead, a location-unavailable state). Reached by tapping a custom game's card,
/// same as a Steam game's card opens `GameDetailView` - launching happens from here, not directly
/// off the grid card, for the same reason it does for Steam games.
struct CustomGameDetailView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    @ObservedObject private var controllerObserver = ControllerObserver.shared
    let game: CustomGame
    let isAdvancedMode: Bool
    let onClose: () -> Void

    @LocalState private var showingSettings = false
    @LocalState private var showingEdit = false
    @LocalState private var focusedActionIndex = 0

    private var runningInfo: RunningProcessInfo? { runningTracker.runningGames[game.id] }
    private var hasCustomSettings: Bool { model.perGameConfigs[game.id] != nil }
    private var isMissing: Bool { !FileManager.default.fileExists(atPath: game.exePath) }

    private var availableActions: [CustomDetailAction] {
        var actions: [CustomDetailAction] = []
        if runningInfo == nil && !isMissing { actions.append(.launch) }
        if isAdvancedMode && !isMissing { actions.append(.settings) }
        if !isMissing { actions.append(.reveal) }
        actions.append(.edit)
        return actions
    }

    private func isFocused(_ action: CustomDetailAction) -> Bool {
        controllerObserver.isConnected && availableActions[safe: focusedActionIndex] == action
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            VStack(alignment: .leading, spacing: 0) {
                closeButton
                ScrollView {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            if let description = game.effectiveAboutTheGame {
                                Text(description)
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            metaRow
                            if isMissing {
                                Label("Game location unavailable", systemImage: "exclamationmark.triangle.fill")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }
                            actionRow
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if hasPhotos {
                            photoColumn
                                .frame(width: 260)
                        }
                    }
                    .padding(32)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .colorScheme(.dark)
        .onExitCommand { onClose() }
        .onChange(of: controllerObserver.directionPress?.token) { _ in
            guard let direction = controllerObserver.directionPress?.direction else { return }
            moveActionFocus(direction)
        }
        .onChange(of: controllerObserver.primaryPress) { _ in
            activateFocusedAction()
        }
        .onChange(of: controllerObserver.secondaryPress) { _ in
            onClose()
        }
        .sheet(isPresented: $showingEdit) {
            EditCustomGameSheet(game: game)
        }
    }

    private func moveActionFocus(_ direction: ControllerDirection) {
        guard !availableActions.isEmpty else { return }
        switch direction {
        case .left, .up: focusedActionIndex = max(0, focusedActionIndex - 1)
        case .right, .down: focusedActionIndex = min(availableActions.count - 1, focusedActionIndex + 1)
        }
    }

    private func activateFocusedAction() {
        switch availableActions[safe: focusedActionIndex] {
        case .launch: model.launchCustomGame(game)
        case .settings: showingSettings = true
        case .reveal: model.revealInFinder(game.exePath)
        case .edit: showingEdit = true
        case nil: break
        }
    }

    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white, .black.opacity(0.4))
        }
        .buttonStyle(.plain)
        .padding(24)
        .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let path = game.discovered.steamBackgroundPath ?? game.effectiveArtworkPath, let image = LocalImageCache.image(atPath: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 50)
                .overlay(Color.black.opacity(0.6))
                .ignoresSafeArea()
        } else {
            LinearGradient(colors: [Color.purple.opacity(0.5), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(game.effectiveName)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                Text("Custom Game")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.85), in: Capsule())
            }
            if game.discovered.steamMetacriticScore != nil || !game.discovered.steamGenres.isEmpty {
                HStack(spacing: 10) {
                    if let score = game.discovered.steamMetacriticScore {
                        metacriticBadge(score)
                    }
                    ForEach(game.discovered.steamGenres.prefix(3), id: \.self) { genre in
                        tag(genre)
                    }
                }
            }
            if !subtitleLine.isEmpty {
                Text(subtitleLine)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    /// True whenever there's actually something to put in `photoColumn`.
    private var hasPhotos: Bool {
        game.effectiveArtworkPath != nil || !game.discovered.steamScreenshotPaths.isEmpty
    }

    /// Every "game photo" (header art, then screenshots) stacked in one column on the right side of
    /// the view - same layout as `GameDetailView`'s own photo column, for the same reason ("for game
    /// photos... move to the right," and "custom game needs everything a steam game has too," per
    /// live feedback). `.aspectRatio(contentMode: .fit)` can never crop or stretch an image
    /// regardless of its real aspect ratio - the fix for a real, separate "it looks squashed"
    /// complaint that a fixed width+height frame with `.fill` risked.
    private var photoColumn: some View {
        VStack(spacing: 12) {
            if let path = game.effectiveArtworkPath, let image = LocalImageCache.image(atPath: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15)))
            }
            ForEach(game.discovered.steamScreenshotPaths, id: \.self) { path in
                if let image = LocalImageCache.image(atPath: path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func metacriticBadge(_ score: Int) -> some View {
        Text("\(score)")
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(metacriticColor(score), in: RoundedRectangle(cornerRadius: 5))
    }

    private func metacriticColor(_ score: Int) -> Color {
        switch score {
        case 75...: return .green
        case 50..<75: return .yellow
        default: return .red
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }

    private var subtitleLine: String {
        var parts: [String] = []
        let developer = game.discovered.steamDevelopers.first ?? game.discovered.publisher
        if let developer { parts.append("By \(developer)") }
        if let releaseDate = game.discovered.steamReleaseDate { parts.append("Released \(releaseDate)") }
        return parts.joined(separator: "  ·  ")
    }


    private var metaRow: some View {
        HStack(spacing: 28) {
            metaItem("Engine", engineBadgeText)
            if let fileVersion = game.discovered.fileVersion {
                metaItem("Version", fileVersion)
            }
        }
    }

    private func metaItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var engineBadgeText: String {
        let config = model.config(forID: game.id)
        return config.d3dMetal ? "D3DMetal" : (config.dxvk ? "DXVK" : (config.dxmt ? "DXMT" : "Default"))
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            if let runningInfo {
                runningBadge(runningInfo)
            } else if isMissing {
                Button("Locate Game") { locateGame() }
                    .buttonStyle(.big)
                    .frame(maxWidth: 220)
                Button("Remove") { model.removeCustomGame(game); onClose() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            } else {
                Button {
                    model.launchCustomGame(game)
                } label: {
                    if model.launchingTarget == .custom(game.id) {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Launching…")
                        }
                    } else {
                        Label("Launch", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.big)
                .disabled(model.launchingTarget != nil)
                .frame(maxWidth: 260)
                .focusRing(isFocused(.launch))
            }
            if isAdvancedMode && !isMissing {
                Button {
                    showingSettings = true
                } label: {
                    Label(hasCustomSettings ? "Custom Settings" : "Settings", systemImage: hasCustomSettings ? "slider.horizontal.3" : "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focusRing(isFocused(.settings))
                .popover(isPresented: $showingSettings) {
                    CustomGameSettingsPopover(game: game)
                }
            }
            if !isMissing {
                Button {
                    model.revealInFinder(game.exePath)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focusRing(isFocused(.reveal))
            }
            Button {
                showingEdit = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .focusRing(isFocused(.edit))
        }
        .padding(.top, 8)
    }

    private func runningBadge(_ info: RunningProcessInfo) -> some View {
        TimelineView(.periodic(from: info.startedAt, by: 60)) { context in
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Running \(elapsedString(from: info.startedAt, to: context.date))")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func elapsedString(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    private func locateGame() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var updated = game
        updated.exePath = url.path
        model.updateCustomGame(updated)
    }
}
