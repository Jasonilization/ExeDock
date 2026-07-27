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
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(message)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                model.runDroppedFile(at: url.path)
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
