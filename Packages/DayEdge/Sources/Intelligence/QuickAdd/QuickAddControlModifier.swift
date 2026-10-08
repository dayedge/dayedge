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
