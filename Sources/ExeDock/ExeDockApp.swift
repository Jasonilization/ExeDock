import SwiftUI

@main
struct ExeDockApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 860, minHeight: 580)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
