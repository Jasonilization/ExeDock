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
    case luxury, glass, brutalist, cyber, soft, pixel, console, minimal
    var id: String { rawValue }

    static let storageKey = "com.exedock.librarySkin"

    /// Plain, grounded names - "make all UI names less cringe... rename all these into better
    /// names less flashy names even," per live feedback. Dropped the trendy prefixes/suffixes
    /// ("Neo-", "Terminal", "Arcade", "Unit", "UI") that read as trying too hard, keeping each
    /// skin's own real identity.
    var displayName: String {
        switch self {
        case .luxury: return "Luxury"
        case .glass: return "Glass"
        case .brutalist: return "Brutalist"
        case .cyber: return "Terminal"
        case .soft: return "Soft"
        case .pixel: return "Pixel"
        case .console: return "Console"
        case .minimal: return "Minimal"
        }
    }

    var accent: Color {
        switch self {
        case .luxury: return Color(red: 0.69, green: 0.55, blue: 0.34)
        case .glass: return Color(red: 0.49, green: 0.36, blue: 1.0)
        case .brutalist: return Color(red: 1.0, green: 0.30, blue: 0.42)
        case .cyber: return Color(red: 0.0, green: 0.94, blue: 1.0)
        case .soft: return Color(red: 0.42, green: 0.45, blue: 1.0)
        case .pixel: return Color(red: 0.96, green: 0.81, blue: 0.48)
        case .console: return Color(red: 1.0, green: 0.48, blue: 0.10)
        case .minimal: return Color(red: 0.04, green: 0.37, blue: 1.0)
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
        case .glass, .soft: return .rounded
        default: return .default
        }
    }

    /// Skins built around a specific dark backdrop (neon-on-black) commit to that single look
    /// rather than trying to also work as a light theme - matches the guidance that a deliberately
    /// single-world design is a legitimate choice, not an oversight.
    var forcesDarkSurface: Bool {
        self == .cyber
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

/// A card's real silhouette under this skin - a plain rounded rect for most, but Cyber Terminal's
/// own distinctive chamfered (cut-corner) shape, ported directly from its mockup's own
/// `clip-path: polygon(14px 0, 100% 0, 100% calc(100% - 14px), calc(100% - 14px) 100%, 0 100%,
/// 0 14px)` - a real structural difference no amount of corner-radius tuning on a plain
/// `RoundedRectangle` can reproduce. "make sure all the format like carasoul, steam style, etc is
/// exactly matching to the quality of the grid layout... right now you only slapped on a wallpaper
/// and font for the other formats," per live feedback - this is the real shape, not an
/// approximation, shared by every layout's cards/tiles alike.
struct PlaydockCardShape: InsettableShape {
    let skin: PlaydockSkin
    let cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard skin == .cyber else {
            return RoundedRectangle(cornerRadius: max(0, cornerRadius - insetAmount), style: .continuous).path(in: rect)
        }
        let cut = max(0, min(14, min(rect.width, rect.height) / 4))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }

    /// Required for `InsettableShape` (what actually makes `.strokeBorder(...)` available - a plain
    /// `Shape` only gets the centered, non-inset `.stroke(...)`, which would draw half the border
    /// outside the shape and get clipped away by the `.clipShape` right after it).
    func inset(by amount: CGFloat) -> PlaydockCardShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Skins whose real mockup card gets a hard, unblurred offset "twin shape" shadow instead of a soft
/// `.shadow()` glow - Neobrutalist's `box-shadow: 8px 8px 0` and Pixel Arcade's `box-shadow: 6px 6px
/// 0` are the same real technique, just different ink colors.
private func hardShadowColor(for skin: PlaydockSkin) -> Color? {
    switch skin {
    case .brutalist: return .primary
    case .pixel: return Color(red: 0.063, green: 0.071, blue: 0.11) // #10121c, the mockup's own ink
    default: return nil
    }
}

private struct CardSurface: ViewModifier {
    var isHovering: Bool = false
    @AppStorage(PlaydockSkin.storageKey) private var skinRaw: String = PlaydockSkin.luxury.rawValue
    private var skin: PlaydockSkin { PlaydockSkin(rawValue: skinRaw) ?? .luxury }

    /// The soft-shadow neumorphic highlight, precomputed as its own small view (not an inline `if`
    /// inside the main chain) - Swift's type checker genuinely cannot solve this many chained
    /// modifiers with conditional ViewBuilder content mixed in as one expression
    /// ("failed to produce diagnostic for expression"), confirmed live against the real compiler,
    /// not a style choice.
    @ViewBuilder
    private func softHighlight(shape: PlaydockCardShape) -> some View {
        if skin == .soft {
            shape.fill(Color(white: colorSchemeIsDark ? 0.16 : 1.0)).offset(x: -6, y: -6).blur(radius: 6).opacity(0.6)
        }
    }

    @ViewBuilder
    private func glassFill(shape: PlaydockCardShape) -> some View {
        if skin == .glass {
            shape.fill(.white.opacity(0.06))
        }
    }

    @ViewBuilder
    private func hardShadowTwin(shape: PlaydockCardShape, color: Color?, offset: CGFloat) -> some View {
        if let color {
            shape.fill(color).offset(x: offset, y: offset)
        }
    }

    func body(content: Content) -> some View {
        let shape = PlaydockCardShape(skin: skin, cornerRadius: skin.cardRadius)
        let hardShadow: Color? = hardShadowColor(for: skin)
        let isSoft = skin == .soft
        let offset: CGFloat = isHovering ? 11 : 7

        let fillStyle: AnyShapeStyle
        if skin == .console {
            fillStyle = AnyShapeStyle(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
        } else if skin == .glass || skin.forcesDarkSurface {
            fillStyle = AnyShapeStyle(.ultraThinMaterial)
        } else {
            fillStyle = AnyShapeStyle(.regularMaterial)
        }

        let borderOpacity: Double = skin == .glass ? 0.35 : (isHovering ? 0.5 : 0.16)
        let borderColor: Color = hardShadow ?? skin.accent.opacity(borderOpacity)

        let shadowColor: Color = isSoft ? .black.opacity(0.22) : (skin.hasShadow ? .black.opacity(isHovering ? 0.30 : 0.16) : .clear)
        let shadowRadius: CGFloat = isSoft ? 10 : (isHovering ? 24 : 12)
        let shadowX: CGFloat = isSoft ? 6 : 0
        let shadowY: CGFloat = isSoft ? 6 : (isHovering ? 12 : 6)
        let hoverPop: CGFloat = (hardShadow != nil && isHovering) ? -3 : 0
        let hoverScale: CGFloat = (isHovering && hardShadow == nil) ? 1.015 : 1

        let step1 = content
            .fontDesign(skin.fontDesign)
            .background(fillStyle, in: shape)
        let step2 = step1
            .background(glassFill(shape: shape))
            .background(softHighlight(shape: shape))
        let step3 = step2
            .overlay(shape.strokeBorder(borderColor, lineWidth: skin.borderWidth))
            .clipShape(shape)
        let step4 = step3
            .background(hardShadowTwin(shape: shape, color: hardShadow, offset: offset))
        return step4
            .shadow(color: shadowColor, radius: shadowRadius, x: shadowX, y: shadowY)
            .offset(x: hoverPop, y: hoverPop)
            .scaleEffect(hoverScale)
            .animation(.easeOut(duration: 0.18), value: isHovering)
    }

    private var colorSchemeIsDark: Bool { NSApp.effectiveAppearance.name == .darkAqua }
}

private struct TileSurface: ViewModifier {
    var isHovering: Bool = false
    @AppStorage(PlaydockSkin.storageKey) private var skinRaw: String = PlaydockSkin.luxury.rawValue
    private var skin: PlaydockSkin { PlaydockSkin(rawValue: skinRaw) ?? .luxury }

    @ViewBuilder
    private func hardShadowTwin(shape: PlaydockCardShape, color: Color?, offset: CGFloat) -> some View {
        if let color {
            shape.fill(color).offset(x: offset, y: offset)
        }
    }

    func body(content: Content) -> some View {
        let shape = PlaydockCardShape(skin: skin, cornerRadius: skin.cardRadius)
        let hardShadow: Color? = hardShadowColor(for: skin)
        let isGlassy = skin == .glass
        let offset: CGFloat = isHovering ? 9 : 6

        let backgroundStyle: AnyShapeStyle = isGlassy ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.clear)
        let borderColor: Color = hardShadow ?? (isGlassy ? skin.accent.opacity(0.3) : Color.white.opacity(0.12))
        let shadowColor: Color = skin.hasShadow ? .black.opacity(isHovering ? 0.35 : 0.25) : .clear
        let shadowRadius: CGFloat = isHovering ? 12 : 8
        let shadowY: CGFloat = isHovering ? 6 : 4
        let hoverScale: CGFloat = (isHovering && hardShadow == nil) ? 1.03 : 1

        // Broken into typed steps - see CardSurface's own doc comment on this same pattern (a real
        // Swift type-checker limitation with this many chained modifiers + conditional content).
        let step1 = content
            // Glass's cards are real translucent panels over whatever's behind them
            // even for a raw art tile - the mockups' own `backdrop-filter: blur(...)` - not just a
            // border and shadow bolted onto opaque art.
            .background(backgroundStyle)
            .clipShape(shape)
        let step2 = step1
            .overlay(shape.strokeBorder(borderColor, lineWidth: skin.borderWidth))
        let step3 = step2
            .background(hardShadowTwin(shape: shape, color: hardShadow, offset: offset))
        return step3
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
            .scaleEffect(hoverScale)
            .animation(.easeOut(duration: 0.16), value: isHovering)
    }
}

/// A real, per-skin button treatment - "for the softUI etc, it should be like the same design for
/// the buttons too," per live feedback: `cardSurface()`/`tileSurface()` got genuine per-skin craft
/// (Cyber's cut corners, Brutalist/Pixel's hard shadow, Soft's neumorphic highlight) while every
/// native button (View Details, Launch, prev/next) stayed a plain, unthemed `.borderedProminent`
/// regardless of skin. Same shape/shadow language as the cards, applied to buttons.
struct PlaydockButtonStyle: ButtonStyle {
    /// `true` for a primary action (View Details/Launch - filled, accent-colored); `false` for a
    /// secondary control (prev/next nav - outlined, quieter).
    var prominent: Bool = true
    @AppStorage(PlaydockSkin.storageKey) private var skinRaw: String = PlaydockSkin.luxury.rawValue
    private var skin: PlaydockSkin { PlaydockSkin(rawValue: skinRaw) ?? .luxury }

    func makeBody(configuration: Configuration) -> some View {
        let shape = PlaydockCardShape(skin: skin, cornerRadius: min(skin.cardRadius, 12))
        let hardShadow: Color? = hardShadowColor(for: skin)
        let isPressed = configuration.isPressed
        let isSoft = skin == .soft

        let fill: AnyShapeStyle
        let labelColor: Color
        if !prominent {
            fill = AnyShapeStyle(Color.clear)
            labelColor = skin.accent
        } else if hardShadow != nil {
            fill = AnyShapeStyle(Color.primary.opacity(0.001)) // stays hit-testable; real fill is .background below
            labelColor = .primary
        } else if skin == .console {
            fill = AnyShapeStyle(LinearGradient(colors: [skin.accent.opacity(0.95), skin.accent], startPoint: .top, endPoint: .bottom))
            labelColor = .black
        } else if skin == .glass {
            fill = AnyShapeStyle(.ultraThinMaterial)
            labelColor = .primary
        } else if isSoft {
            fill = AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
            labelColor = skin.accent
        } else {
            fill = AnyShapeStyle(skin.accent)
            labelColor = .white
        }

        let borderColor: Color = prominent ? (hardShadow ?? .clear) : skin.accent.opacity(0.5)
        let borderWidth: CGFloat = prominent ? (hardShadow != nil ? skin.borderWidth : 0) : 1.5
        let pressOffset: CGFloat = (hardShadow != nil && isPressed) ? 4 : 0

        return configuration.label
            .font(.callout.weight(.semibold))
            .fontDesign(skin.fontDesign)
            .foregroundStyle(labelColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(fill, in: shape)
            // Soft UI's real neumorphic raised/pressed toggle - inset shadow when pressed, raised
            // dual-shadow otherwise, matching cardSurface()'s own treatment.
            .background(alignment: .center) {
                if isSoft && !isPressed {
                    shape.fill(Color.black.opacity(0.12)).offset(x: 3, y: 3).blur(radius: 4)
                }
            }
            .overlay(shape.strokeBorder(borderColor, lineWidth: borderWidth))
            .clipShape(shape)
            .background(alignment: .center) {
                if let hardShadow {
                    shape.fill(hardShadow).offset(x: pressOffset == 0 ? 5 : 1, y: pressOffset == 0 ? 5 : 1)
                }
            }
            .offset(x: pressOffset, y: pressOffset)
            .shadow(color: isPressed ? .clear : Color.black.opacity(skin.hasShadow ? 0.18 : 0), radius: 6, y: 3)
            .scaleEffect(isPressed && hardShadow == nil ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}

extension View {
    /// A lighter version of `cardSurface()` for a raw art tile (the new library layouts' poster/
    /// icon tiles) - just the skin's corner radius, border, and shadow, with no material fill
    /// layered on top of real artwork the way a content card needs. Reads the same `PlaydockSkin`
    /// so every layout's tiles restyle together with the grid's own cards.
    func tileSurface(isHovering: Bool = false) -> some View {
        modifier(TileSurface(isHovering: isHovering))
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
    case grid, shelves, sidebar, list, steam, carousel, spotlight
    var id: String { rawValue }

    static let storageKey = "com.exedock.libraryLayout"

    var displayName: String {
        switch self {
        case .grid: return "Grid"
        case .shelves: return "Shelves"
        case .sidebar: return "Sidebar"
        case .list: return "List"
        case .steam: return "Steam-style"
        case .carousel: return "Carousel"
        case .spotlight: return "Spotlight"
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
        case .spotlight: return "One game up close, browsable, + a grid"
        }
    }
}

/// Which real art a card/tile shows for a Steam game - "have the option to use either the app icon
/// or the banner for the main art on boxes," per live feedback, after "the UI for the other ones...
/// all the games are cropped" turned out to be a real, fixable gap: every portrait-shaped tile
/// (Carousel, Steam-style, List/Sidebar's small icons) was force-cropping the landscape
/// `header.jpg` banner rather than using Steam's own real, *native* portrait box art
/// (`library_600x900.jpg`, cached locally by the real Steam client - see `SteamLibraryCache`).
/// `.banner` keeps the existing landscape header everywhere (matches the mockups' own card shape);
/// `.boxArt` uses Steam's native portrait art where a game has it cached, falling back to the
/// banner for anything Steam hasn't cached yet (never viewed in Steam's own library) or a custom
/// game (no Steam cache to read at all).
enum PlaydockArtSource: String, CaseIterable, Identifiable {
    case banner, boxArt
    var id: String { rawValue }
    static let storageKey = "com.exedock.artSource"
    var displayName: String {
        switch self {
        case .banner: return "Banner"
        case .boxArt: return "Box Art"
        }
    }
    var subtitle: String {
        switch self {
        case .banner: return "Steam's landscape store banner"
        case .boxArt: return "Steam's native portrait box art, where cached"
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
