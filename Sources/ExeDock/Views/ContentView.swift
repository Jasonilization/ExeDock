import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @LocalState private var isTargeted = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedSection) {
                Label("Library", systemImage: "square.grid.2x2").tag(AppModel.SidebarSection.library)
                Label("C: Drive", systemImage: "internaldrive").tag(AppModel.SidebarSection.cDrive)
                Label("Game Mode", systemImage: "gamecontroller").tag(AppModel.SidebarSection.gameMode)
                Label("About", systemImage: "info.circle").tag(AppModel.SidebarSection.about)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            VStack(spacing: 0) {
                dropZone
                Divider()
                content
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        browseForExecutable()
                    } label: {
                        Label("Select EXE…", systemImage: "doc.badge.plus")
                    }
                    Button {
                        model.installAndRunSteam()
                    } label: {
                        Label("Install & Run Steam", systemImage: "gamecontroller.fill")
                    }
                    .disabled(model.isInstallingSteam)
                }
            }
        }
        .alert("ExeDock", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedSection {
        case .library:
            LibraryView()
        case .cDrive:
            CDriveView()
        case .gameMode:
            GameModeView()
        case .about:
            AboutView()
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 26))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text(isTargeted ? "Drop to run" : "Drag an .exe here to run it")
                .font(.callout)
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
        .padding(18)
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
