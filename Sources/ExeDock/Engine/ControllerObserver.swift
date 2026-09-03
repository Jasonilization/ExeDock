import Foundation
import GameController

enum ControllerDirection {
    case up, down, left, right
}

/// Tracks whether a game controller is currently connected, using Apple's own `GameController`
/// framework - a real, first-party API, not something rebuilt from scratch. Also the single owner
/// of every button/D-pad handler on the controller - LB/RB step between top-level sections (see
/// `ContentView`'s `stepSection(by:)`), LT/RT step between games in whichever layout has a single
/// featured/focused game to step through (Carousel, Shelves, Spotlight); D-pad/A/B are published as
/// generic signals any view can subscribe to and react to *only while it's the active input layer*
/// (its own `isActiveLayer`-style check on its own state), rather than each view fighting over the
/// same raw `GCExtendedGamepad` handler properties directly. That "single owner, many self-filtering
/// subscribers" split is what lets the grid, the Game Detail view, and the dedicated Controller Mode
/// carousel all support real D-pad/A/B navigation without colliding - whichever one is actually on
/// top just ignores signals when it isn't. Everything here is purely event-driven
/// (`GCControllerDidConnect`/`DidDisconnect` notifications, `pressedChangedHandler`), so this costs
/// nothing while idle.
@MainActor
final class ControllerObserver: ObservableObject {
    static let shared = ControllerObserver()

    @Published private(set) var isConnected: Bool
    /// Cleared automatically whenever a controller (re)connects, so dismissing the banner for one
    /// session doesn't silently suppress it forever.
    @Published var bannerDismissed = false
    /// Bumped exactly once on every real (re)connect - `nil` at launch if a controller happened to
    /// already be attached before this ever became visible. Purely a UI trigger (the brief green
    /// "controller connected" glow next to the tab switcher) - `isConnected` is still the source of
    /// truth for whether one is attached right now.
    @Published private(set) var connectedPulse: UUID?
    /// Bumped whenever LB/RB is pressed - direction is -1/+1, `token` changes every time so a
    /// repeated press in the same direction still triggers `.onChange` in `ContentView`. Kept as a
    /// plain signal rather than a direct reference to `AppModel`, so this observer doesn't need to
    /// know anything about the app's specific section type.
    @Published private(set) var sectionStepRequest: (direction: Int, token: UUID)?
    /// Bumped whenever LT/RT is pressed - "step to the previous/next game" for whichever layout
    /// currently has one game singled out (Carousel's focused tile, Shelves/Spotlight's featured
    /// hero). Kept separate from `directionPress` since D-pad left/right already means something
    /// different in some of those same layouts (Carousel's own row navigation).
    @Published private(set) var gameStepRequest: (direction: Int, token: UUID)?
    /// Bumped on every D-pad press (button-edge, not continuous) - `token` changes every time so a
    /// repeated press in the same direction still triggers `.onChange` for whichever view is
    /// currently treating itself as the active input layer.
    @Published private(set) var directionPress: (direction: ControllerDirection, token: UUID)?
    /// Bumped on every A-button press - "confirm/select whatever's focused."
    @Published private(set) var primaryPress: UUID?
    /// Bumped on every B-button press - "back/close/cancel."
    @Published private(set) var secondaryPress: UUID?

    /// The real, currently-attached controller's own SF Symbol names for each button this app
    /// actually uses (Apple's `GCExtendedGamepad` hands these back per-element, matched to whatever
    /// is really plugged in - an Xbox pad reports its own glyphs, a DualSense reports PlayStation's,
    /// an MFi pad its own generic ones) - so the on-screen control legend shows the real glyph for
    /// the real hardware instead of one guessed icon painted over every controller alike. Falls back
    /// to a plain, reasonable SF Symbol when nothing's connected (the legend only ever renders while
    /// `isConnected` anyway, but every accessor stays safe to call regardless).
    var dpadSymbol: String { activeGamepad?.dpad.sfSymbolsName ?? "dpad" }
    var buttonASymbol: String { activeGamepad?.buttonA.sfSymbolsName ?? "a.circle" }
    var buttonBSymbol: String { activeGamepad?.buttonB.sfSymbolsName ?? "b.circle" }
    var leftShoulderSymbol: String { activeGamepad?.leftShoulder.sfSymbolsName ?? "l.rectangle.roundedbottom" }
    var rightShoulderSymbol: String { activeGamepad?.rightShoulder.sfSymbolsName ?? "r.rectangle.roundedbottom" }
    var leftTriggerSymbol: String { activeGamepad?.leftTrigger.sfSymbolsName ?? "l2.rectangle.roundedbottom" }
    var rightTriggerSymbol: String { activeGamepad?.rightTrigger.sfSymbolsName ?? "r2.rectangle.roundedbottom" }
    private var activeGamepad: GCExtendedGamepad? { GCController.controllers().first?.extendedGamepad }

    private init() {
        isConnected = !GCController.controllers().isEmpty
        if let controller = GCController.controllers().first {
            attachGlobalHandlers(to: controller)
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in self?.handleConnect(notification) }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func handleConnect(_ notification: Notification) {
        refresh(justConnected: true)
        if let controller = notification.object as? GCController {
            attachGlobalHandlers(to: controller)
        }
    }

    private func refresh(justConnected: Bool = false) {
        isConnected = !GCController.controllers().isEmpty
        if justConnected, isConnected {
            bannerDismissed = false
            connectedPulse = UUID()
        }
    }

    private func attachGlobalHandlers(to controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.sectionStepRequest = (-1, UUID()) }
        }
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.sectionStepRequest = (1, UUID()) }
        }
        gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.gameStepRequest = (-1, UUID()) }
        }
        gamepad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.gameStepRequest = (1, UUID()) }
        }

        // `pressedChangedHandler` (button-edge semantics: fires once per press/release), not
        // `valueChangedHandler` (fires continuously while held) - the latter would fire dozens of
        // times a second while a direction is held, jumping through focus far too fast.
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.directionPress = (.up, UUID()) }
        }
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.directionPress = (.down, UUID()) }
        }
        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.directionPress = (.left, UUID()) }
        }
        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.directionPress = (.right, UUID()) }
        }
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.primaryPress = UUID() }
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.secondaryPress = UUID() }
        }
    }
}
