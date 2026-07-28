import SwiftUI

/// A gentle fade-and-scale pop used everywhere something appears asynchronously - a row once its
/// icon/data resolves, a list once a background scan finishes, etc. Self-contained on `onAppear`
/// rather than requiring every call site to wrap its state mutation in `withAnimation`, so it stays
/// correct however the surrounding data got there (initial load, a search filter, a background
/// refresh, ...).
private struct FadeInOnAppear: ViewModifier {
    @LocalState private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.92)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func fadeInOnAppear() -> some View {
        modifier(FadeInOnAppear())
    }
}
