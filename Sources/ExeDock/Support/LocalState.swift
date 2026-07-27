import SwiftUI

/// Drop-in replacement for `@State`. This machine only has Command Line Tools installed (no
/// Xcode.app), and this SDK's `@State` attribute expands via the external `SwiftUIMacros`
/// compiler plugin, which Command Line Tools doesn't ship - so `@State` fails to build here.
/// The underlying `SwiftUI.State<Value>` storage type is still a plain, fully public struct
/// (used by the macro internally), so this wrapper drives it directly without needing the plugin.
@propertyWrapper
struct LocalState<Value>: DynamicProperty {
    private var storage: SwiftUI.State<Value>

    init(wrappedValue: Value) {
        storage = SwiftUI.State(wrappedValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> {
        storage.projectedValue
    }
}
