import SwiftUI

/// Provides an onChange-like view modifier that supplies both the old and new
/// value to the handler. This avoids relying on SDK-specific overloads and
/// compiles consistently across Xcode versions.
struct OnChangeOldModifier<Value: Equatable>: ViewModifier {
    @State private var previous: Value
    private let value: Value
    private let action: (Value, Value) -> Void

    init(value: Value, action: @escaping (Value, Value) -> Void) {
        self.value = value
        self._previous = State(initialValue: value)
        self.action = action
    }

    func body(content: Content) -> some View {
        content.onChange(of: value) { newValue in
            action(previous, newValue)
            previous = newValue
        }
    }
}

extension View {
    /// Call a handler with the previous and new value whenever `value` changes.
    func onChangeOld<Value: Equatable>(of value: Value, perform: @escaping (Value, Value) -> Void) -> some View {
        modifier(OnChangeOldModifier(value: value, action: perform))
    }
}
