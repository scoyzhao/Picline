#if compiler(<5.9)
import AppKit
import SwiftUI

// All callers are synchronous AppKit callbacks on the main thread.
extension MainActor {
    static func assumeIsolated<T>(_ operation: @MainActor () throws -> T) rethrows -> T {
        precondition(Thread.isMainThread)
        return try withoutActuallyEscaping(operation) { isolated in
            try unsafeBitCast(isolated, to: (() throws -> T).self)()
        }
    }
}

private struct LegacyChange<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (Value, Value) -> Void
    @State private var previous: Value

    init(value: Value, action: @escaping (Value, Value) -> Void) {
        self.value = value
        self.action = action
        _previous = State(initialValue: value)
    }

    func body(content: Content) -> some View {
        content.onChange(of: value) { newValue in
            let oldValue = previous
            previous = newValue
            action(oldValue, newValue)
        }
    }
}

extension View {
    func onChange<Value: Equatable>(of value: Value,
                                   _ action: @escaping (Value, Value) -> Void) -> some View {
        modifier(LegacyChange(value: value, action: action))
    }
}
#endif
