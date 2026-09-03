import SwiftUI

/// A simple, reliable linear controller-focus loop for a flat list of `count` items - not 2D-aware
/// (a real grid's actual column count depends on the window's current width for every `.adaptive`
/// grid in this app, which none of these layouts currently measure), but it guarantees every item
/// is reachable by repeated same-direction D-pad presses and that A activates whichever one is
/// currently focused. Left/up move back, right/down move forward, both clamped rather than
/// wrapped - the same predictable, no-surprise-jump convention `GameDetailView`'s own action-row
/// focus already uses. Each layout using this still owns its own `focusedIndex` state and computes
/// `isFocused` per item itself (so it can show a real `focusRing()`), and gates all of it on
/// `ControllerObserver.isConnected` - mouse-only use is completely unaffected.
private struct ControllerLinearFocus: ViewModifier {
    @ObservedObject private var controllerObserver = ControllerObserver.shared
    @Binding var focusedIndex: Int?
    let count: Int
    let onActivate: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: controllerObserver.directionPress?.token) { _ in
                guard count > 0, let direction = controllerObserver.directionPress?.direction else { return }
                let current = focusedIndex ?? 0
                switch direction {
                case .left, .up: focusedIndex = max(0, current - 1)
                case .right, .down: focusedIndex = min(count - 1, current + 1)
                }
            }
            .onChange(of: controllerObserver.primaryPress) { _ in
                guard count > 0, controllerObserver.isConnected else { return }
                onActivate(focusedIndex ?? 0)
            }
    }
}

extension View {
    func controllerLinearFocus(focusedIndex: Binding<Int?>, count: Int, onActivate: @escaping (Int) -> Void) -> some View {
        modifier(ControllerLinearFocus(focusedIndex: focusedIndex, count: count, onActivate: onActivate))
    }
}
