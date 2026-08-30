import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var controllerObserver = ControllerObserver.shared
    @LocalState private var isTargeted = false
    /// A global "make everything bigger or smaller" zoom, per live feedback ("add a UI slider at
    /// the very bottom left so stuff can be big or small. like everyhting."). Applied as a single
    /// `.scaleEffect` on the whole app's content rather than threading a scale factor through every
    /// individual font/frame/padding value in the app - genuinely scales *everything* (text, icons,
    /// cards, spacing) at once, the literal ask, for a fraction of the engineering cost. The
    /// trade-off: scaling up can extend content past the window's own edges the same way it would
    /// for any "zoom" control, rather than growing the window to compensate - the window is
    /// resizable, so that's a reasonable, standard behavior (the same one a browser's page zoom or
    /// a code editor's font-size zoom already has).
    @AppStorage("com.exedock.uiScale") private var uiScale: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            VStack(spacing: 0) {
                // The Steam dashboard has its own header/search/launch flow - the generic drop
                // zone and toolbar only make sense on the Exe Loader side, so they'd just be visual
                // noise (and a distraction from "just click your game") on the main tab.
                if model.selectedSection != .gameMode {
                    dropZone
                    Divider()
                }
                content
            }
        }
        .scaleEffect(uiScale, anchor: .topLeading)
        .alert("Playdock", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onChange(of: controllerObserver.sectionStepRequest?.token) { _ in
            guard let direction = controllerObserver.sectionStepRequest?.direction else { return }
            stepSection(by: direction)
        }
        // Deliberately chained after `.scaleEffect` above, not before: `.scaleEffect` is a
        // render-time transform, not a layout-time one, so an `.overlay` added afterward still
        // gets positioned against the *original*, unscaled window bounds - meaning this slider
        // stays put at the window's real bottom-left corner and at a constant, readable size no
        // matter what `uiScale` itself is currently set to.
        .overlay(alignment: .bottomLeading) {
            uiScaleSlider
        }
    }

    private var uiScaleSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "textformat.size.smaller")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $uiScale, in: 0.75...1.5, step: 0.05)
                .frame(width: 130)
            Image(systemName: "textformat.size.larger")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(14)
        .help("UI Size (\(Int(uiScale * 100))%)")
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    // MARK: - Top bar

    /// A compact, always-in-the-same-spot switcher instead of a full sidebar column - keeps the
    /// window's whole width for the dashboard, and (unlike a sidebar list) is something a
    /// controller can drive directly: LT/RT step through it from anywhere in the app, wired
    /// globally by `ControllerObserver` rather than needing this specific view to be focused.
    private var topBar: some View {
        HStack(spacing: 14) {
            sectionSwitcher
            Spacer()
            if model.selectedSection != .gameMode {
                Button {
                    browseForExecutable()
                } label: {
                    Label("Select EXE…", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                Button {
                    model.installAndRunSteam()
                } label: {
                    Label("Install & Run Steam", systemImage: "gamecontroller.fill")
                }
                .buttonStyle(.bordered)
                .disabled(model.isInstallingSteam)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sectionSwitcher: some View {
        HStack(spacing: 10) {
            sectionButton(.gameMode)
            // A small visual gap, not a label - Steam still reads as the primary destination and
            // Library/C: Drive as the secondary, grouped "Exe Loader" pair, just without spending a
            // whole sidebar section header on it.
            Divider().frame(height: 20)
            HStack(spacing: 4) {
                sectionButton(.library)
                sectionButton(.cDrive)
            }
        }
    }

    private func sectionButton(_ section: AppModel.SidebarSection) -> some View {
        let isSelected = model.selectedSection == section
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { model.selectedSection = section }
        } label: {
            Label(title(for: section), systemImage: icon(for: section))
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 46, height: 36)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .help(title(for: section))
    }

    private func title(for section: AppModel.SidebarSection) -> String {
        switch section {
        case .gameMode: return "Steam"
        case .library: return "Library"
        case .cDrive: return "C: Drive"
        }
    }

    private func icon(for section: AppModel.SidebarSection) -> String {
        switch section {
        case .gameMode: return "gamecontroller.fill"
        case .library: return "square.grid.2x2"
        case .cDrive: return "internaldrive"
        }
    }

    /// Wired to the controller's LT (-1) / RT (+1) triggers via `ControllerObserver`, so paging
    /// between Steam/Library/C: Drive works from anywhere in the app, not just inside the dedicated
    /// Controller Mode carousel.
    private func stepSection(by direction: Int) {
        let all = AppModel.SidebarSection.allCases
        guard let currentIndex = all.firstIndex(of: model.selectedSection) else { return }
        let newIndex = (currentIndex + direction + all.count) % all.count
        withAnimation(.easeInOut(duration: 0.2)) {
            model.selectedSection = all[newIndex]
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch model.selectedSection {
            case .gameMode:
                GameModeView()
            case .library:
                LibraryView()
            case .cDrive:
                CDriveView()
            }
        }
        .id(model.selectedSection)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: model.selectedSection)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 34))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text(isTargeted ? "Drop to run" : "Drag an .exe here to run it")
                .font(.title3)
            if let status = model.statusMessage {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            if case .installing(let message) = model.steamStatus {
                VStack(spacing: 4) {
                    ProgressView(value: nil as Double?)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 260)
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        .animation(.default, value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileURLType = UTType.fileURL.identifier
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(fileURLType) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: fileURLType, options: nil) { item, _ in
            let url: URL?
            switch item {
            case let data as Data:
                url = URL(dataRepresentation: data, relativeTo: nil)
            case let nsurl as NSURL:
                url = nsurl as URL
            case let plainURL as URL:
                url = plainURL
            default:
                url = nil
            }
            guard let resolvedURL = url else { return }
            DispatchQueue.main.async {
                model.runDroppedFile(at: resolvedURL.path)
            }
        }
        return true
    }

    private func browseForExecutable() {
        let panel = NSOpenPanel()
        if let exeType = UTType(filenameExtension: "exe") {
            panel.allowedContentTypes = [exeType]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            model.runDroppedFile(at: url.path)
        }
    }
}
