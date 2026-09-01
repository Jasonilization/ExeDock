import SwiftUI

/// Shared visual language for Playdock's dashboard - a small, consistent set of tokens plus a
/// reusable "floating card" treatment, so cards/panels read as one deliberate design instead of
/// independently-tuned one-offs. Built around a real surface scale (each layer reads as sitting
/// *on top of* the one below it, via material + border + shadow) - the same layering approach
/// well-regarded library/dashboard apps (Steam's own library, GOG Galaxy 2.0) use to make a dense
/// grid of cards read as separate, touchable objects rather than a flat wall of boxes. "Redesign
/// the whole app's look... research how good this kinda UI is," per live feedback.
enum Playdock {
    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 12
        static let pill: CGFloat = 999
    }

    enum Spacing {
        /// Gap between cards in the library grid - wider than a typical control-spacing value on
        /// purpose, so the grid reads as a set of distinct objects with real room to breathe
        /// instead of tiles packed edge to edge.
        static let grid: CGFloat = 24
    }
}

private struct CardSurface: ViewModifier {
    var isHovering: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Playdock.Radius.card, style: .continuous)
        content
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(isHovering ? 0.16 : 0.08), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(isHovering ? 0.30 : 0.16), radius: isHovering ? 24 : 12, y: isHovering ? 12 : 6)
            .scaleEffect(isHovering ? 1.015 : 1)
            .animation(.easeOut(duration: 0.18), value: isHovering)
    }
}

extension View {
    /// The one shared "floating card" treatment used across the game grid - rounded, materialed,
    /// bordered, properly clipped (an unclipped `.background` shape alone lets square-cornered
    /// content like artwork visibly overflow past the rounded corners underneath it), and shadowed
    /// with a genuine lift on hover, matching real game-library card conventions instead of a flat,
    /// borderless rectangle with no depth.
    func cardSurface(isHovering: Bool = false) -> some View {
        modifier(CardSurface(isHovering: isHovering))
    }
}
