import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ExeDock").font(.title).bold()
            Text("A lightweight drag-and-drop UI for running Windows .exe files on the Mac making it easy to run your windows applications quickly.")
                .foregroundStyle(.secondary)

            Divider()

            Text("Under the hood!").font(.headline)
            Text("""
            ExeDock doesn't reimplement Windows compatibility - it runs on the same Sikarugir \
            engine already installed on this Mac (the engine behind Sikarugir Creator and \
            wrapper apps it's already built). ExeDock reuses that engine to run any .exe you \
            drop on it inside its own private bottle, and never modifies Sikarugir Creator or \
            any wrapper app it has already created.
            """)
            .fixedSize(horizontal: false, vertical: true)

            Button("Open Sikarugir Creator") {
                model.openSikarugirCreator()
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
