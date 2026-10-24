import SwiftUI
import UI

/// The shell every Quick Add editor shares: its picker, a link that removes the value (Remove Date, All Day, Never) and
/// Done. Return or Done closes it.
struct QuickAddPopover<Picker: View>: View {
    var removeTitle: String?
    var remove: () -> Void = {}
    let close: () -> Void
    @ViewBuilder let picker: Picker

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            picker
                .labelsHidden()
            HStack {
                if let removeTitle {
                    Button(removeTitle) {
                        remove()
                        close()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
                Spacer()
                Button(L10n.tr("quickaddeditorview.done", "Done"), action: close)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .onKeyPress(.return) { close(); return .handled }
    }
}
