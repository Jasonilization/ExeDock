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

/// A game card's "this is running right now" state - a plain static status tag with a soft
/// breathing pulse on the dot, not a live-ticking elapsed-time counter. Deliberately dropped the
/// minute counter this replaced: "running status not very good... 0m never actually changes," per
/// live feedback - a real bug (detection flickering resets the remembered start time, so the
/// counter can get stuck near zero indefinitely) traced back to how Steam/GOG Galaxy/Playnite
/// actually handle this in their own library grids too - none of them show a live-updating per-
/// minute clock on a card; a simple "Playing"/"Running" state tag is the real, established
/// convention. Removing the number removes the whole class of bug instead of chasing every way
/// detection can flicker.
struct RunningBadge: View {
    /// The full-width card version (default) fills its row and uses the standard `.quaternary`
    /// card-language background; `compact: true` is a tighter pill for a context that already sits
    /// on its own dark/blurred backdrop (the Game Detail views' action row), matching the white-
    /// on-translucent treatment that row's other elements already use.
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            PulsingDot()
            Text("Running")
                .font(.callout.weight(.medium))
                .foregroundStyle(compact ? .white : .primary)
        }
        .frame(maxWidth: compact ? nil : .infinity)
        .padding(.horizontal, compact ? 16 : 0)
        .padding(.vertical, compact ? 10 : 12)
        .background(
            compact ? AnyShapeStyle(.white.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.5)),
            in: RoundedRectangle(cornerRadius: compact ? 10 : Playdock.Radius.control)
        )
    }
}

/// The shared breathing/pulsing green dot behind every "Running" indicator - a soft expanding ring
/// that fades out and loops, the same "this is live, right now" convention notification badges and
/// recording indicators use, rather than a numeric readout that can only ever be as reliable as
/// the underlying process-detection polling.
private struct PulsingDot: View {
    @LocalState private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color.green.opacity(isPulsing ? 0 : 0.5), lineWidth: 4)
                    .scaleEffect(isPulsing ? 2.2 : 1)
            )
            .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
