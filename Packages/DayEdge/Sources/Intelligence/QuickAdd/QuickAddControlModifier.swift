import SwiftUI

extension View {
    /// A Quick Add field control: focusable (no system ring — it draws its
    /// own), and a click, Space or Return opens its editor.
    func quickAddControl(_ field: QuickAddField, focus: FocusState<QuickAddField?>.Binding,
                         open: @escaping () -> Void) -> some View {
        focusable()
            .focusEffectDisabled()
            .focused(focus, equals: field)
            .onTapGesture(perform: open)
            .onKeyPress(keys: [.space, .return]) { _ in
                open()
                return .handled
            }
    }
}

extension KeyEquivalent {
    /// How far an arrow key steps a closed control's value: ← / → by `small`, ↑ / ↓ by `large`, ← and ↑ backwards.
    /// Days step 1 and 7, times 15 and 60 minutes. Any other key does not step.
    func step(small: Int, large: Int) -> Int {
        switch self {
        case .leftArrow: -small
        case .rightArrow: small
        case .upArrow: -large
        case .downArrow: large
        default: 0
        }
    }
}
