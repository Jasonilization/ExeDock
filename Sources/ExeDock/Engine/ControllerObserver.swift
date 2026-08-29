import Foundation
import GameController

enum ControllerDirection {
    case up, down, left, right
}

/// Tracks whether a game controller is currently connected, using Apple's own `GameController`
/// framework - a real, first-party API, not something rebuilt from scratch. Also the single owner
/// of every button/D-pad handler on the controller - LT/RT step between top-level sections (see
/// `ContentView`'s `stepSection(by:)`); D-pad/A/B are published as generic signals any view can
/// subscribe to and react to *only while it's the active input layer* (its own `isActiveLayer`-style
/// check on its own state), rather than each view fighting over the same raw
/// `GCExtendedGamepad` handler properties directly. That "single owner, many self-filtering
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
    /// Bumped whenever LT/RT is pressed - direction is -1/+1, `token` changes every time so a
    /// repeated press in the same direction still triggers `.onChange` in `ContentView`. Kept as a
    /// plain signal rather than a direct reference to `AppModel`, so this observer doesn't need to
    /// know anything about the app's specific section type.
    @Published private(set) var sectionStepRequest: (direction: Int, token: UUID)?
    /// Bumped on every D-pad press (button-edge, not continuous) - `token` changes every time so a
    /// repeated press in the same direction still triggers `.onChange` for whichever view is
    /// currently treating itself as the active input layer.
    @Published private(set) var directionPress: (direction: ControllerDirection, token: UUID)?
    /// Bumped on every A-button press - "confirm/select whatever's focused."
    @Published private(set) var primaryPress: UUID?
    /// Bumped on every B-button press - "back/close/cancel."
    @Published private(set) var secondaryPress: UUID?

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
        }
    }

    private func attachGlobalHandlers(to controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.sectionStepRequest = (-1, UUID()) }
        }
        gamepad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.sectionStepRequest = (1, UUID()) }
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
