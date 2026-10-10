import Domain
import SwiftUI

/// How wide a property editor is — tokens, not per-editor numbers.
package enum PropertyEditorWidth {
    case compact, standard, wide
    /// The control's own size (a calendar picker) — no empty band beside it.
    case fit

    package var points: CGFloat? {
        switch self {
        case .compact: return 200
        case .standard: return 250
        case .wide: return 300
        case .fit: return nil
        }
    }
}

/// The one shell every anchored property editor uses (Time, Date, a
/// specific alert, …): the same padding, width classes and footer. With
/// `onDone`, a draft is edited and the footer is Cancel · Done, trailing —
/// ↩ is Done and Esc is Cancel, consumed here (the editor is its own
/// popover, so they never reach the card or the panel behind it).
package struct PropertyEditor<Content: View>: View {
    @Environment(\.themePalette) private var theme

    package var width: PropertyEditorWidth = .standard
    package var onCancel: (() -> Void)?
    package var onDone: (() -> Void)?
    @ViewBuilder package let content: () -> Content

    package var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
            if let onDone {
                Divider().overlay(theme.chrome.divider)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button(L10n.tr("propertyeditor.cancel", "Cancel")) { onCancel?() }
                        .keyboardShortcut(.cancelAction)
                    Button(L10n.tr("propertyeditor.done", "Done"), action: onDone)
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.small)
            }
        }
        .font(DetailMetrics.font)
        .padding(12)
        .frame(width: width.points, alignment: .leading)
        .fixedSize(horizontal: width.points == nil, vertical: false)
        .selectorPopoverSurface(theme)
    }
}

/// The date editors' calendar, as the shared shell holds it: its own size,
/// no AppKit focus frame around it (↑↓←→ still move the day).
package struct PropertyEditorCalendar: View {
    @Binding package var selection: Date

    package var body: some View {
        DatePicker("", selection: $selection, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.graphical)
            .focusEffectDisabled()
    }
}

/// A labelled control inside a property editor: "Starts   11:15".
package struct PropertyEditorField<Control: View>: View {
    @Environment(\.themePalette) private var theme

    package let label: String
    @ViewBuilder package let control: () -> Control

    package var body: some View {
        HStack {
            Text(label).foregroundStyle(theme.secondaryText)
            Spacer(minLength: 8)
            control()
        }
    }
}
