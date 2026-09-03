import SwiftUI

/// A thin green line that glows under the top tab switcher for a couple of seconds right when a
/// controller connects, then fades away on its own - "a green light on the top with the disk and
/// game tab... a green line glowing meaning controller connected (appears briefly)," per live
/// feedback. Reads `ControllerObserver.connectedPulse` (bumped once per real connect event, not
/// `isConnected` itself) so this fires exactly once per connect rather than staying lit the whole
/// time a controller is attached - the persistent "Controller connected" banner already covers
/// that ongoing state; this is just the moment-of-connection confirmation.
struct ControllerConnectedGlow: View {
    @ObservedObject private var controllerObserver = ControllerObserver.shared
    @LocalState private var isVisible = false

    var body: some View {
        Capsule()
            .fill(Color.green)
            .frame(height: 3)
            .shadow(color: .green.opacity(0.9), radius: 6)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(false)
            .onChange(of: controllerObserver.connectedPulse) { pulse in
                guard pulse != nil else { return }
                Task {
                    withAnimation(.easeIn(duration: 0.15)) { isVisible = true }
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    withAnimation(.easeOut(duration: 0.5)) { isVisible = false }
                }
            }
    }
}

/// One button-and-what-it-does pair for the on-screen control legend below.
struct ControllerHint: Identifiable {
    let symbol: String
    let label: String
    var id: String { symbol + label }
}

/// A slim, persistent strip of "which button does what" - shown only while a controller is
/// connected, matching the same on-screen-prompt convention real console dashboards use instead of
/// expecting a player to guess or dig through a settings screen. Reads the real, currently-attached
/// controller's own SF Symbol glyphs (`ControllerObserver`'s symbol accessors) rather than one fixed
/// icon set, so an Xbox pad shows Xbox-style glyphs and a DualSense shows PlayStation's. Each screen
/// passes only the hints actually relevant to it - Grid's own card navigation doesn't need to
/// mention LT/RT if nothing on screen responds to it.
struct ControllerLegendBar: View {
    let hints: [ControllerHint]
    @ObservedObject private var controllerObserver = ControllerObserver.shared

    var body: some View {
        if controllerObserver.isConnected, !hints.isEmpty {
            // Centered, not packed against the leading edge - "UI toggle also blocking visibility
            // of controller navigation help," a real, confirmed collision with the UI-size slider
            // that already lives fixed in the window's own bottom-left corner (ContentView's
            // `uiScaleSlider`). Centering keeps this clear of that corner on any real window width
            // instead of hand-tuning a leading inset to match one specific control's own size.
            HStack(spacing: 18) {
                Spacer()
                ForEach(hints) { hint in
                    HStack(spacing: 6) {
                        Image(systemName: hint.symbol)
                            .font(.callout.weight(.semibold))
                        Text(hint.label)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: controllerObserver.isConnected)
        }
    }
}

extension ControllerObserver {
    /// The standard "move focus / select / back" trio every controller-navigable screen offers -
    /// shared so each screen doesn't hand-roll its own copy of the same three hints.
    var moveSelectBackHints: [ControllerHint] {
        [
            ControllerHint(symbol: dpadSymbol, label: "Move"),
            ControllerHint(symbol: buttonASymbol, label: "Select"),
            ControllerHint(symbol: buttonBSymbol, label: "Back"),
        ]
    }
    var switchTabHint: ControllerHint {
        ControllerHint(symbol: "l.rectangle.roundedbottom", label: "Switch Tab (LB/RB)")
    }
    var switchGameHint: ControllerHint {
        ControllerHint(symbol: "l2.rectangle.roundedbottom", label: "Switch Game (LT/RT)")
    }
}
