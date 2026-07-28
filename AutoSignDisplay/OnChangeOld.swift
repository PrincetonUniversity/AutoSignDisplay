import SwiftUI

/// An onChange-like modifier that hands the handler both the old and the new value.
///
/// The two-parameter `onChange` has existed since tvOS 17 and this app targets 18.4,
/// so the shim no longer tracks the previous value itself — it just forwards. What it
/// still buys is a stable call-site spelling: every `onChangeOld` in the app keeps
/// working, and the single-parameter overload it used to call is deprecated and warns.
struct OnChangeOldModifier<Value: Equatable>: ViewModifier {
    private let value: Value
    private let action: (Value, Value) -> Void

    init(value: Value, action: @escaping (Value, Value) -> Void) {
        self.value = value
        self.action = action
    }

    func body(content: Content) -> some View {
        content.onChange(of: value) { oldValue, newValue in
            action(oldValue, newValue)
        }
    }
}

extension View {
    /// Call a handler with the previous and new value whenever `value` changes.
    func onChangeOld<Value: Equatable>(of value: Value, perform: @escaping (Value, Value) -> Void) -> some View {
        modifier(OnChangeOldModifier(value: value, action: perform))
    }
}
