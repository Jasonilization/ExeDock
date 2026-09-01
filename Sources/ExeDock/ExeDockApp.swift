import SwiftUI
import CoreText

@main
struct ExeDockApp: App {
    init() {
        SkinFonts.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 1180, minHeight: 780)
                // Cascades to every button/picker/toggle/text field in the app - one place to make
                // controls bigger and easier to hit instead of tuning `.controlSize` per view.
                .controlSize(.large)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
