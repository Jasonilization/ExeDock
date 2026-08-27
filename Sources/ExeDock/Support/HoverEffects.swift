import SwiftUI

/// A playful hover-and-press treatment for icon-shaped elements (avatars, launch tiles) - lifts the
/// icon toward the cursor (scale up, rises slightly, shadow deepens beneath it) while it does one
/// slow 3D turn around its vertical axis, like a coin/card tipping up off the surface; pressing it
/// pushes it back down into the surface instead. Deliberately not applied to plain text buttons or
/// wide artwork - it's for things that read as "an icon."
private struct HoverSpin: ViewModifier {
    @LocalState private var isHovering = false
    @LocalState private var isPressed = false
    @LocalState private var spinDegrees: Double = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.93 : (isHovering ? 1.12 : 1.0))
            .offset(y: isPressed ? 5 : (isHovering ? -8 : 0))
            .rotation3DEffect(.degrees(spinDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .shadow(
                color: .black.opacity(isPressed ? 0.12 : (isHovering ? 0.3 : 0)),
                radius: isPressed ? 6 : (isHovering ? 18 : 0),
                y: isPressed ? 3 : (isHovering ? 12 : 0)
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
            .animation(.spring(response: 0.45, dampingFraction: 0.65), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    withAnimation(.easeInOut(duration: 2.2)) { spinDegrees += 360 }
                }
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
