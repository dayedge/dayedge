import AppKit
import UI

/// The independent meeting slot. Its text changes without rendering a bitmap.
@MainActor
final class MenuBarMeetingItemController {
    var onCalendarClick: () -> Void = {}
    var onContextMenu: (NSStatusItem) -> Void = { _ in }
    private(set) var statusItem: NSStatusItem?
    private var onJoin: (() -> Void)?
    private let renderer = MenuBarMeetingRenderer()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "\(Bundle.main.bundleIdentifier ?? "com.dayedge.app").status.meeting"
        item.isVisible = false
        if let button = item.button {
            button.imageScaling = .scaleNone
            button.imagePosition = .imageLeft
            button.imageHugsTitle = true
            button.font = AppTheme.MenuBar.meetingFont
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    func apply(_ presentation: MenuBarMeetingPresentation?, toolTip: String?, onJoin: (() -> Void)?) {
        self.onJoin = presentation == nil ? nil : onJoin
        guard let item = statusItem, let button = item.button else { return }
        guard let presentation else {
            item.isVisible = false
            button.image = nil
            button.title = ""
            button.toolTip = nil
            return
        }
        let scale = button.window?.screen?.backingScaleFactor ?? 2
        let content = renderer.render(presentation, scale: scale)
        if button.image !== content.image { button.image = content.image }
        if button.title != content.text { button.title = content.text }
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip ?? content.text)
        item.isVisible = true
    }

    @objc private func clicked() {
        guard let item = statusItem, let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            onContextMenu(item)
        } else if let onJoin {
            onJoin()
        } else {
            onCalendarClick()
        }
    }
}
