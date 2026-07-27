import SwiftUI

@main
struct ExeDockApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 860, minHeight: 580)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
