import SwiftUI

/// A subtle hover-and-press treatment for icon-shaped elements (avatars, launch tiles) - a gentle
/// lift with a slow, continuous 3D turn around its vertical axis for as long as the cursor stays
/// over it (stops smoothly on exit), and a light push-down on press. Deliberately not applied to
/// plain text buttons or wide artwork - it's for things that read as "an icon."
private struct HoverSpin: ViewModifier {
    @LocalState private var isHovering = false
    @LocalState private var isPressed = false
    @LocalState private var rotationDegrees: Double = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.97 : (isHovering ? 1.04 : 1.0))
            .offset(y: isPressed ? 2 : (isHovering ? -3 : 0))
            .rotation3DEffect(.degrees(rotationDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .shadow(
                color: .black.opacity(isPressed ? 0.08 : (isHovering ? 0.18 : 0)),
                radius: isPressed ? 4 : (isHovering ? 10 : 0),
                y: isPressed ? 2 : (isHovering ? 6 : 0)
            )
            .onHover { hovering in
                // Explicit withAnimation per mutation, on purpose - stacking multiple implicit
                // `.animation(_:value:)` modifiers on one view and changing more than one of their
                // values in the same tick (isHovering and the spin both flip together here) lets
                // SwiftUI apply the wrong modifier's curve to a given property. That's what made the
                // spin run at spring speed instead of its own slow linear one before this rewrite.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isHovering = hovering
                }
                if hovering {
                    withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                        rotationDegrees += 360
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.4)) {
                        rotationDegrees = rotationDegrees.truncatingRemainder(dividingBy: 360)
                    }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isPressed = true }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isPressed = false }
                    }
            )
    }
}

/// Just a press-down nudge, no hover effects at all - for the Steam launch tile, which turned out
/// to want less going on than a full `hoverSpin()`.
private struct PressPush: ViewModifier {
    @LocalState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .offset(y: isPressed ? 5 : 0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { isPressed = true }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { isPressed = false }
                    }
            )
    }
}

extension View {
    func hoverSpin() -> some View {
        modifier(HoverSpin())
    }

    func pressPush() -> some View {
        modifier(PressPush())
    }
}
