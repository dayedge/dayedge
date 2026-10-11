import AppKit
import Foundation
import Domain
import UI

/// Owns the primary icon/date item, its popover anchor and the shared status menu.
@MainActor
final class MenuBarStatusItemController {
    var onCalendarClick: () -> Void = {}
    var onAnchorChange: (PopoverAnchor) -> Void = { _ in }
    /// The right-click menu's rows, resolved fresh each time it opens.
    var menuPlan: () -> [[StatusMenuItem]] = { [[.settings], [.quit]] }
    /// A menu row was chosen (Quit and About are handled here).
    var onMenuAction: (StatusMenuItem) -> Void = { _ in }
    /// Mute Until › one of its options.
    var onMuteUntil: (MuteUntilOption) -> Void = { _ in }

    private var statusItem: NSStatusItem?
    private let images = MenuBarImageCache<MenuBarBadgeImageKey>()
    private var anchorObservers: [NSObjectProtocol] = []

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "\(Bundle.main.bundleIdentifier ?? "com.dayedge.app").status.primary"
        item.isVisible = true
        if let button = item.button {
            button.font = AppTheme.MenuBar.primaryFont
            button.imagePosition = .imageLeft
            button.imageHugsTitle = true
            // Without this, `NSButton` can stretch/resample the icon to
            // fit its own content box — this icon is drawn at its exact
            // intended size already, so it should render 1:1, not be
            // rescaled by the button.
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(statusItemClicked)
            // The button only sends its action for a left click by
            // default — right/control-click needs to be opted into
            // explicitly to reach the same handler, where it's routed to
            // the context menu instead of the calendar-click callback.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        observeAnchorChanges()
    }

    func apply(badge: MenuBarBadgeContent, cornerGlyph: MenuBarCornerGlyph?, text: String, showsIcon: Bool) {
        guard let button = statusItem?.button else { return }
        let scale = button.window?.screen?.backingScaleFactor ?? 2
        let key = MenuBarBadgeImageKey(number: badge.number, glyph: cornerGlyph, scale: scale)
        let image = showsIcon ? images.image(for: key) {
            MenuBarBadgeIcon.render(value: badge.number, cornerGlyph: cornerGlyph, scale: scale)
        } : nil
        if button.image !== image { button.image = image }
        button.imagePosition = showsIcon ? .imageLeft : .noImage
        if button.title != text { button.title = text }
        button.setAccessibilityLabel(text.isEmpty ? "DayEdge" : "DayEdge, \(text)")
    }

    /// Anchor to the icon when present, otherwise the date/time button's center.
    var screenAnchor: PopoverAnchor? {
        guard let button = statusItem?.button, let frame = buttonScreenFrame,
              let screen = button.window?.screen, let cell = button.cell else { return nil }
        let anchorX = button.image == nil ? button.bounds.midX : cell.imageRect(forBounds: button.bounds).midX
        return PopoverAnchor(
            point: CGPoint(x: frame.minX + anchorX, y: frame.minY),
            visibleFrame: screen.visibleFrame
        )
    }

    /// The status item button's frame on screen.
    var buttonScreenFrame: CGRect? {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return nil }
        return buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func observeAnchorChanges() {
        guard let button = statusItem?.button, let window = button.window else { return }
        button.postsFrameChangedNotifications = true
        button.postsBoundsChangedNotifications = true
        let notifications: [(Notification.Name, AnyObject?)] = [
            (NSView.frameDidChangeNotification, button),
            (NSView.boundsDidChangeNotification, button),
            (NSWindow.didMoveNotification, window),
            (NSWindow.didResizeNotification, window),
            (NSWindow.didChangeScreenNotification, window),
            (NSWindow.didChangeBackingPropertiesNotification, window),
            (NSApplication.didChangeScreenParametersNotification, nil)
        ]
        anchorObservers = notifications.map { name, object in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let anchor = self.screenAnchor else { return }
                    self.onAnchorChange(anchor)
                }
            }
        }
    }

    deinit {
        anchorObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
            return
        }

        onCalendarClick()
    }

    /// Shown on right/control-click instead of toggling the popover.
    /// `NSStatusItem.menu`, if left set permanently, would hijack *every*
    /// click (left included) into showing the menu instead of calling the
    /// button's action — so it's only assigned right before popping the
    /// menu up, and cleared right after `performClick` (which blocks
    /// until the menu is dismissed) returns, restoring normal left-click
    /// toggling for next time.
    func showContextMenu(for meetingItem: NSStatusItem? = nil) {
        guard let item = meetingItem ?? statusItem, let button = item.button else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, section) in menuPlan().enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for row in section {
                menu.addItem(menuItem(for: row))
                // Restart is for troubleshooting: only with ⌥ held.
                if case .quit = row { menu.addItem(restartItem()) }
            }
        }

        item.menu = menu
        button.performClick(nil)
        item.menu = nil
    }

    private func menuItem(for row: StatusMenuItem) -> NSMenuItem {
        let item = NSMenuItem(title: row.title, action: #selector(chooseRow(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = RowBox(row)
        // The title says it; AppKit sizes, tints and highlights the symbol.
        if let symbol = row.symbolName {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            if #available(macOS 27.0, *) {
                // Public ImageVisibility.visible = 1; KVC keeps the Xcode 26 SDK and CLT buildable.
                item.setValue(1, forKey: "preferredImageVisibility")
            }
        }
        switch row {
        case .settings:
            item.keyEquivalent = ","
        case .quit:
            item.keyEquivalent = "q"
        case .pauseAlerts(let options, let isPaused, let checked):
            // Like Focus: Resume first while paused, then the durations —
            // text only, the chosen one checked when it still holds.
            item.action = nil
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            if isPaused {
                submenu.addItem(menuItem(for: .unmuteAll))
                submenu.addItem(.separator())
            }
            for option in options {
                let choice = NSMenuItem(title: option.menuTitle, action: #selector(chooseMuteUntil(_:)), keyEquivalent: "")
                choice.target = self
                choice.representedObject = option.rawValue
                choice.state = option == checked ? .on : .off
                submenu.addItem(choice)
            }
            item.submenu = submenu
        default:
            break
        }
        return item
    }

    private func restartItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.tr("menubarstatusitemcontroller.restart.dayedge", "Restart DayEdge"), action: #selector(restart), keyEquivalent: "q")
        item.keyEquivalentModifierMask = [.command, .option]
        item.isAlternate = true
        item.target = self
        return item
    }

    @objc private func chooseRow(_ sender: NSMenuItem) {
        guard let row = (sender.representedObject as? RowBox)?.row else { return }
        switch row {
        case .quit: NSApp.terminate(nil)
        case .about:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        default: onMenuAction(row)
        }
    }

    @objc private func chooseMuteUntil(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let option = MuteUntilOption(rawValue: raw) else { return }
        onMuteUntil(option)
    }

    /// Relaunches the exact binary currently running, then quits this
    /// instance — a plain `open`/`NSWorkspace` relaunch would instead
    /// launch whatever `.app` bundle macOS associates with the identifier,
    /// not necessarily this on-disk build.
    @objc private func restart() {
        let executablePath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        try? process.run()
        NSApp.terminate(nil)
    }
}

/// `representedObject` needs an object; the row is an enum.
private final class RowBox {
    let row: StatusMenuItem
    init(_ row: StatusMenuItem) { self.row = row }
}
