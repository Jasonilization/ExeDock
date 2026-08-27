import SwiftUI

/// A subtle hover-and-press treatment for icon-shaped elements (avatars, launch tiles) - a gentle
/// lift with a slow, continuous 3D turn around its vertical axis for as long as the cursor stays
/// over it (stops smoothly on exit), and a light push-down on press. Deliberately not applied to
/// plain text buttons or wide artwork - it's for things that read as "an icon."
private struct HoverSpin: ViewModifier {
    @LocalState private var isHovering = false
    @LocalState private var isPressed = false
    @LocalState private var isSpinning = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.97 : (isHovering ? 1.04 : 1.0))
            .offset(y: isPressed ? 2 : (isHovering ? -3 : 0))
            .rotation3DEffect(.degrees(isSpinning ? 360 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .shadow(
                color: .black.opacity(isPressed ? 0.08 : (isHovering ? 0.18 : 0)),
                radius: isPressed ? 4 : (isHovering ? 10 : 0),
                y: isPressed ? 2 : (isHovering ? 6 : 0)
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHovering)
            .animation(
                isSpinning ? .linear(duration: 3.5).repeatForever(autoreverses: false) : .easeOut(duration: 0.4),
                value: isSpinning
            )
            .onHover { hovering in
                isHovering = hovering
                isSpinning = hovering
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    func hoverSpin() -> some View {
        modifier(HoverSpin())
    }
}
