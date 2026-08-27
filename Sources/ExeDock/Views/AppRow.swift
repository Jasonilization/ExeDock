import SwiftUI

struct AppRow: View {
    @EnvironmentObject private var model: AppModel
    let app: DetectedApp

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIconProvider.icon(for: app))
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.body)
                Text(app.exePath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if app.bottle.isReadOnly {
                Text("Sikarugir")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Button {
                model.revealInFinder(app.exePath)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.bordered)
            Button("Run") {
                model.run(exePath: app.exePath, bottle: app.bottle)
            }
            .font(.headline)
            .padding(.vertical, 4)
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }
}
