import SwiftUI

/// Gates the main UI behind `SetupCoordinator` so the app can detect and prepare a Sikarugir
/// engine (and ExeDock's own bottle) automatically the first time it's launched.
struct RootView: View {
    @StateObject private var setup = SetupCoordinator()
    @StateObject private var model = AppModel()

    var body: some View {
        Group {
            if setup.stage == .ready {
                ContentView()
                    .environmentObject(model)
            } else {
                SetupView(setup: setup)
            }
        }
        .onAppear {
            setup.runSetup()
        }
        .onChange(of: setup.stage) { newStage in
            if newStage == .ready {
                model.onSetupReady()
            }
        }
    }
}
