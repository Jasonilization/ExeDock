import SwiftUI

/// Shared visual language for Playdock's dashboard - a small, consistent set of tokens plus a
/// reusable "floating card" treatment, so cards/panels read as one deliberate design instead of
/// independently-tuned one-offs. Built around a real surface scale (each layer reads as sitting
/// *on top of* the one below it, via material + border + shadow) - the same layering approach
/// well-regarded library/dashboard apps (Steam's own library, GOG Galaxy 2.0) use to make a dense
/// grid of cards read as separate, touchable objects rather than a flat wall of boxes.
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

/// The library's "look" - an independent axis from `LibraryLayoutStyle` (its *structure*), so any
/// layout can be paired with any skin. Each skin is a small set of real, native tokens (accent
/// color, corner radius, and a system `Font.Design` - `.rounded`/`.serif`/`.monospaced` are real,
/// built-in SwiftUI font variants, not custom typefaces that would need bundling) rather than 10
/// hand-painted screens - "keep them as skins for each [layout]," per live feedback. Persisted via
/// `@AppStorage` the same way `isAdvancedMode`/`uiScale` already are elsewhere in this app.
enum PlaydockSkin: String, CaseIterable, Identifiable {
    case luxury, glass, brutalist, cyber, soft, editorial, pixel, console, minimal, vapor
    var id: String { rawValue }

    static let storageKey = "com.exedock.librarySkin"

    var displayName: String {
        switch self {
        case .luxury: return "Quiet Luxury"
        case .glass: return "Glass"
        case .brutalist: return "Neobrutalist"
        case .cyber: return "Cyber Terminal"
        case .soft: return "Soft UI"
        case .editorial: return "Editorial"
        case .pixel: return "Pixel Arcade"
        case .console: return "Console Unit"
        case .minimal: return "Minimal"
        case .vapor: return "Vaporwave"
        }
    }

    var accent: Color {
        switch self {
        case .luxury: return Color(red: 0.69, green: 0.55, blue: 0.34)
        case .glass: return Color(red: 0.49, green: 0.36, blue: 1.0)
        case .brutalist: return Color(red: 1.0, green: 0.30, blue: 0.42)
        case .cyber: return Color(red: 0.0, green: 0.94, blue: 1.0)
        case .soft: return Color(red: 0.42, green: 0.45, blue: 1.0)
        case .editorial: return Color(red: 0.54, green: 0.43, blue: 0.23)
        case .pixel: return Color(red: 0.96, green: 0.81, blue: 0.48)
        case .console: return Color(red: 1.0, green: 0.48, blue: 0.10)
        case .minimal: return Color(red: 0.04, green: 0.37, blue: 1.0)
        case .vapor: return Color(red: 1.0, green: 0.18, blue: 0.90)
        }
    }

    /// A card's own corner radius under this skin - brutalist/pixel go sharp, everything else
    /// stays rounded to some degree.
    var cardRadius: CGFloat {
        switch self {
        case .brutalist, .pixel: return 4
        case .console: return 10
        case .cyber: return 8
        default: return Playdock.Radius.card
        }
    }

    var fontDesign: Font.Design {
        switch self {
        case .brutalist, .cyber, .pixel: return .monospaced
        case .glass, .soft, .vapor: return .rounded
        case .editorial: return .serif
        default: return .default
        }
    }

    /// Skins built around a specific dark backdrop (neon-on-black, retrowave gradient) commit to
    /// that single look rather than trying to also work as a light theme - matches the guidance
    /// that a deliberately single-world design is a legitimate choice, not an oversight.
    var forcesDarkSurface: Bool {
        self == .cyber || self == .vapor
    }

    /// The real, root-cause fix for "every skin's cards look like the same generic grey box":
    /// nothing was ever pinning the skin's OWN light/dark identity, so system-adaptive colors
    /// (`Color.primary`, `.regularMaterial`, default text) quietly followed the *system's* Dark
    /// Mode instead - a light skin like Brutalist got a cream `SkinBackground` (hardcoded RGB, so
    /// that part always looked right) paired with `Color.primary` resolving to *white* (because the
    /// Mac is in Dark Mode), making its "black" 3px border invisible against its own light card.
    /// Every skin whose `SkinBackground` is a hardcoded light or dark treatment now pins that same
    /// identity here via `.preferredColorScheme`, so its materials/text/borders render against the
    /// appearance the skin was actually designed for - independent of the user's system setting.
    /// Luxury/Minimal deliberately return `nil` (follow system) since their own backgrounds already
    /// do the same (`.windowBackgroundColor`/`.textBackgroundColor`).
    var colorScheme: ColorScheme? {
        switch self {
        case .luxury, .minimal: return nil
        case .glass, .brutalist, .soft, .editorial: return .light
        case .cyber, .pixel, .console, .vapor: return .dark
        }
    }

    var borderWidth: CGFloat {
        self == .brutalist ? 3 : 1
    }

    var hasShadow: Bool {
        self != .brutalist && self != .soft
    }

    /// The real, bundled display face for this skin's most prominent text (falls back to a bold
    /// system font in this same `fontDesign` for a skin that deliberately has no display face of
    /// its own - see `SkinFonts`'s own doc comment for why).
    func displayFont(size: CGFloat) -> Font {
        if let name = SkinFonts.postscriptName(for: self) {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: .bold, design: fontDesign)
    }
}

/// A title/headline that renders in the active skin's own real display face - the one thing that
/// actually makes switching skins look like switching identities rather than just recoloring the
/// same system font. Used everywhere a game's name is the most prominent text on screen (grid
/// cards, every new library layout's tiles/heroes).
struct SkinTitleText: View {
    let text: String
    var size: CGFloat = 17
    var lineLimit: Int? = 1
    @AppStorage(PlaydockSkin.storageKey) private var skinRaw: String = PlaydockSkin.luxury.rawValue
    private var skin: PlaydockSkin { PlaydockSkin(rawValue: skinRaw) ?? .luxury }

    var body: some View {
        Text(text)
            .font(skin.displayFont(size: size))
            .lineLimit(lineLimit)
    }
}

private struct CardSurface: ViewModifier {
    var isHovering: Bool = false
    @AppStorage(PlaydockSkin.storageKey) private var skinRaw: String = PlaydockSkin.luxury.rawValue
    private var skin: PlaydockSkin { PlaydockSkin(rawValue: skinRaw) ?? .luxury }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.cardRadius, style: .continuous)
        let offset: CGFloat = isHovering ? 11 : 7
        content
            .fontDesign(skin.fontDesign)
            .background(
                skin == .glass ? AnyShapeStyle(.ultraThinMaterial)
                    : skin.forcesDarkSurface ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial),
                in: shape
            )
            .background(skin == .glass ? shape.fill(.white.opacity(0.06)) : nil)
            .overlay(shape.strokeBorder(skin == .brutalist ? Color.primary : skin.accent.opacity(skin == .glass ? 0.35 : (isHovering ? 0.5 : 0.16)), lineWidth: skin.borderWidth))
            .clipShape(shape)
            // Neobrutalist gets its own real, hard (unblurred) offset shadow - a solid-color twin
            // shape behind the card, not `.shadow()` (which always blurs) - matching the mockup's
            // own `box-shadow: 8px 8px 0` exactly instead of approximating it as a soft glow.
            .background(alignment: .center) {
                if skin == .brutalist {
                    shape.fill(Color.primary).offset(x: offset, y: offset)
                }
            }
            .shadow(color: skin.hasShadow ? .black.opacity(isHovering ? 0.30 : 0.16) : .clear, radius: isHovering ? 24 : 12, y: isHovering ? 12 : 6)
            .offset(x: skin == .brutalist && isHovering ? -3 : 0, y: skin == .brutalist && isHovering ? -3 : 0)
            .scaleEffect(isHovering && skin != .brutalist ? 1.015 : 1)
            .animation(.easeOut(duration: 0.18), value: isHovering)
    }
}

private struct TileSurface: ViewModifier {
    @AppStorage(PlaydockSkin.storageKey) private var skinRaw: String = PlaydockSkin.luxury.rawValue
    private var skin: PlaydockSkin { PlaydockSkin(rawValue: skinRaw) ?? .luxury }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.cardRadius, style: .continuous)
        content
            .clipShape(shape)
            .overlay(shape.strokeBorder(skin == .brutalist ? Color.primary : Color.white.opacity(0.12), lineWidth: skin.borderWidth))
            .shadow(color: skin.hasShadow ? .black.opacity(0.25) : .clear, radius: 8, y: 4)
    }
}

extension View {
    /// A lighter version of `cardSurface()` for a raw art tile (the new library layouts' poster/
    /// icon tiles) - just the skin's corner radius, border, and shadow, with no material fill
    /// layered on top of real artwork the way a content card needs. Reads the same `PlaydockSkin`
    /// so every layout's tiles restyle together with the grid's own cards.
    func tileSurface() -> some View {
        modifier(TileSurface())
    }
}

extension View {
    /// The one shared "floating card" treatment used across the game grid - rounded, materialed,
    /// bordered, properly clipped (an unclipped `.background` shape alone lets square-cornered
    /// content like artwork visibly overflow past the rounded corners underneath it), and shadowed
    /// with a genuine lift on hover, matching real game-library card conventions instead of a flat,
    /// borderless rectangle with no depth. Reads the active `PlaydockSkin` itself, so every card
    /// everywhere restyles together the instant the skin setting changes.
    func cardSurface(isHovering: Bool = false) -> some View {
        modifier(CardSurface(isHovering: isHovering))
    }

    /// Applies just the skin's accent color and font design, for non-card surfaces (headers,
    /// buttons, layout chrome) that still need to restyle with the active skin.
    func skinned() -> some View {
        modifier(SkinTint())
    }
}

private struct SkinTint: ViewModifier {
    @AppStorage(PlaydockSkin.storageKey) private var skinRaw: String = PlaydockSkin.luxury.rawValue
    private var skin: PlaydockSkin { PlaydockSkin(rawValue: skinRaw) ?? .luxury }
    func body(content: Content) -> some View {
        content.fontDesign(skin.fontDesign).tint(skin.accent)
    }
}

/// The library's *structure* - independent from `PlaydockSkin` (its look). Each case is a real,
/// distinct navigation model, not a reskinned grid - researched against actual, proven app
/// patterns before building: Steam's own current library (sidebar + tag-filtered grid), PS5/Xbox
/// home screens (hero + horizontal shelves), Music.app (sidebar list + big detail pane), a plain
/// dense table (Playnite's list mode), and Apple TV's poster carousel - "search actual game
/// design... maybe just dont have cards," per live feedback. A seventh, Launchpad-style bare icon
/// grid was tried and removed: "the one with dense and only small icons have no art delete that
/// one" - a dense grid of generic small icons was never going to read as a real, distinct design
/// the way each of the remaining six genuinely does.
enum LibraryLayoutStyle: String, CaseIterable, Identifiable {
    case grid, shelves, sidebar, list, steam, carousel
    var id: String { rawValue }

    static let storageKey = "com.exedock.libraryLayout"

    var displayName: String {
        switch self {
        case .grid: return "Grid"
        case .shelves: return "Shelves"
        case .sidebar: return "Sidebar"
        case .list: return "List"
        case .steam: return "Steam-style"
        case .carousel: return "Poster Carousel"
        }
    }

    var subtitle: String {
        switch self {
        case .grid: return "Cards in a grid - the default"
        case .shelves: return "Featured hero + horizontal rows"
        case .sidebar: return "List with a big detail pane"
        case .list: return "Dense table, no artwork"
        case .steam: return "Sidebar categories + poster grid"
        case .carousel: return "One row, focus scales up"
        }
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
