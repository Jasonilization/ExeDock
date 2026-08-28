import Foundation
import GameController

/// Tracks whether a game controller is currently connected, using Apple's own `GameController`
/// framework - a real, first-party API, not something rebuilt from scratch. Also owns the one bit
/// of controller input that should work everywhere in the app, not just inside the dedicated
/// Controller Mode carousel: LT/RT step between top-level sections (see `ContentView`'s
/// `stepSection(by:)`). Both are purely event-driven (`GCControllerDidConnect`/`DidDisconnect`
/// notifications, `pressedChangedHandler`), so this costs nothing while idle.
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

    /// LT/RT only - Controller Mode's own D-pad/A/B handlers (attached separately, while that view
    /// is showing) live on different buttons, so there's no collision between the two.
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
    }
}
