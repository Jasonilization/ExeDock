import Foundation
import GameController

/// Tracks whether a game controller is currently connected, using Apple's own `GameController`
/// framework - a real, first-party API, not something rebuilt from scratch. Purely event-driven
/// (`GCControllerDidConnect`/`DidDisconnect` notifications), so this costs nothing while idle.
@MainActor
final class ControllerObserver: ObservableObject {
    static let shared = ControllerObserver()

    @Published private(set) var isConnected: Bool
    /// Cleared automatically whenever a controller (re)connects, so dismissing the banner for one
    /// session doesn't silently suppress it forever.
    @Published var bannerDismissed = false

    private init() {
        isConnected = !GCController.controllers().isEmpty
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh(justConnected: true) }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh(justConnected: false) }
        }
    }

    private func refresh(justConnected: Bool) {
        isConnected = !GCController.controllers().isEmpty
        if justConnected, isConnected {
            bannerDismissed = false
        }
    }
}
