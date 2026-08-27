import SwiftUI

/// A chunky, console-dashboard-style button - bigger than SwiftUI's `.large` control size caps out
/// at, for the handful of actions that should dominate the screen (Launch, Install & Run Steam).
/// `prominent` picks solid-accent-fill vs. a quieter secondary fill. Hovering brightens and lifts it
/// slightly; pressing pushes it down into the surface, like a real console button.
struct BigButtonStyle: ButtonStyle {
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        BigButtonLabel(configuration: configuration, prominent: prominent)
    }
}

private struct BigButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @LocalState private var isHovering = false

    var body: some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(
                prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.6)),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .brightness(configuration.isPressed ? 0 : (isHovering ? 0.06 : 0))
            .scaleEffect(configuration.isPressed ? 0.94 : (isHovering ? 1.02 : 1.0))
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

extension ButtonStyle where Self == BigButtonStyle {
    static var big: BigButtonStyle { BigButtonStyle() }
    static func big(prominent: Bool) -> BigButtonStyle { BigButtonStyle(prominent: prominent) }
}
