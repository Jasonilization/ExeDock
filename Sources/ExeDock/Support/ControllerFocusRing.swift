import SwiftUI

private struct ControllerFocusRing: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: isFocused ? 4 : 0)
                    .padding(-4)
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

extension View {
    /// A visible highlight for whatever a controller's D-pad currently has selected - an
    /// accent-colored ring just outside the view's own bounds plus a slight scale-up, so it reads
    /// clearly as "this is what A will activate" without needing a cursor on screen. Used by both
    /// the games grid (`GameCardView`) and the Game Detail view's action row.
    func focusRing(_ isFocused: Bool) -> some View {
        modifier(ControllerFocusRing(isFocused: isFocused))
    }
}
