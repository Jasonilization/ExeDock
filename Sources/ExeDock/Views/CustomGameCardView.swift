import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Visually mirrors `GameCardView`'s layout (art/title/details/Launch) but wired to `CustomGame`/
/// `AppModel.launchCustomGame` instead of Steam - its own small view rather than sharing
/// `GameCardView` directly, since the two kinds diverge in real ways (a "Custom Game" badge, no
/// Steam-only launch overlay, a location-unavailable state Steam games can never hit). The settings
/// popover and Inspect section underneath are shared, generalized code, though - see
/// `CustomGameSettingsPopover`.
struct CustomGameCardView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var runningTracker = RunningGameTracker.shared
    let game: CustomGame
    let isAdvancedMode: Bool
    let artworkHeight: CGFloat
    let isFocused: Bool

    @LocalState private var showingSettings = false
    @LocalState private var showingEdit = false

    private var runningInfo: RunningProcessInfo? { runningTracker.runningGames[game.id] }
    private var hasCustomSettings: Bool { model.perGameConfigs[game.id] != nil }
    private var isMissing: Bool { !FileManager.default.fileExists(atPath: game.exePath) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.effectiveName)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                        Text("Custom Game")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.85), in: Capsule())
                    }
                    Spacer()
                    if isAdvancedMode {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: hasCustomSettings ? "slider.horizontal.3" : "gearshape")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .help(hasCustomSettings ? "Custom settings" : "Game settings")
                        .popover(isPresented: $showingSettings) {
                            CustomGameSettingsPopover(game: game)
                        }
                    }
                }
                if let description = game.effectiveDescription {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if isMissing {
                    Label("Game location unavailable", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let runningInfo {
                    runningBadge(runningInfo)
                } else if isMissing {
                    HStack(spacing: 10) {
                        Button("Locate Game") { locateGame() }
                            .buttonStyle(.bordered)
                        Button("Remove") { model.removeCustomGame(game) }
                            .buttonStyle(.bordered)
                    }
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
                            Text("Launch")
                        }
                    }
                    .buttonStyle(.big)
                    .disabled(model.launchingTarget != nil)
                }
            }
            .padding(20)
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .focusRing(isFocused)
        .contextMenu {
            Button {
                model.revealInFinder(game.exePath)
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(game.exePath, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            Button {
                showingEdit = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                model.removeCustomGame(game)
            } label: {
                Label("Remove From Library", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditCustomGameSheet(game: game)
        }
        .onHover { isHovering in
            if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let path = game.effectiveArtworkPath, let image = LocalImageCache.image(atPath: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: artworkHeight * 0.3))
                    .foregroundStyle(Color.purple)
                    .frame(maxWidth: .infinity)
                    .background(Color.purple.opacity(0.15))
            }
        }
        .frame(height: artworkHeight)
        .clipped()
    }

    private func runningBadge(_ info: RunningProcessInfo) -> some View {
        TimelineView(.periodic(from: info.startedAt, by: 60)) { context in
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Running \(elapsedString(from: info.startedAt, to: context.date))")
                    .font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func elapsedString(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    /// Re-runs the same file picker used to add a game in the first place - only updates `exePath`,
    /// never touches anything else about the record (name overrides, discovered metadata, etc.).
    private func locateGame() {
        let panel = NSOpenPanel()
        if let exeType = UTType(filenameExtension: "exe") { panel.allowedContentTypes = [exeType] }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var updated = game
        updated.exePath = url.path
        model.updateCustomGame(updated)
    }
}
