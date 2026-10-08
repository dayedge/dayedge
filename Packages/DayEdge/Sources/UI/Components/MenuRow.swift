import SwiftUI

/// One native context-menu item: the title with its SF Symbol (or plain
/// text) and the key shown beside it. The event and task menus share it.
package struct MenuRow: View {
    let title: String
    let symbol: String?
    var role: ButtonRole?
    var shortcut: KeyboardShortcut?
    let action: () -> Void

    package init(_ title: String, symbol: String?, role: ButtonRole? = nil, shortcut: KeyboardShortcut? = nil,
                 action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.shortcut = shortcut
        self.action = action
    }

    package var body: some View {
        Button(role: role, action: action) {
            if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
        }
        .keyboardShortcut(shortcut)
    }
}
