import AppKit
import Foundation
import Domain

/// A dumb AppKit shell around the single `NSStatusItem` — owns the button,
/// its click-region math (calendar half vs. accessory half), and its
/// right-click context menu. Never touches `CalendarDataProviding`,
/// `AgendaEventModel`, or any `*Strategy`/`*Settings` type: it only applies
/// whatever image/tooltip/accessory region it's handed via `apply(...)`
/// and reports clicks back through closures. `MenuBarStateController`
/// decides *what* to show; this only shows it.
@MainActor
final class MenuBarStatusItemController {
    var onCalendarClick: () -> Void = {}
    /// The right-click menu's rows, resolved fresh each time it opens.
    var menuPlan: () -> [[StatusMenuItem]] = { [[.settings], [.quit]] }
    /// A menu row was chosen (Quit and About are handled here).
    var onMenuAction: (StatusMenuItem) -> Void = { _ in }
    /// Mute Until › one of its options.
    var onMuteUntil: (MuteUntilOption) -> Void = { _ in }

    private var statusItem: NSStatusItem?
    private var accessoryRegionMinX: CGFloat?
    private var onAccessoryClick: (() -> Void)?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
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
    }

    /// Sole way anything outside this controller changes what's shown.
    /// `onAccessoryClick` fires instead of `onCalendarClick` when a click
    /// lands in the accessory's region — nil when there's currently
    /// nothing joinable, in which case every click is a calendar click.
    func apply(image: NSImage?, toolTip: String?, accessoryRegionMinX: CGFloat?, onAccessoryClick: (() -> Void)?) {
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = toolTip
        self.accessoryRegionMinX = accessoryRegionMinX
        self.onAccessoryClick = onAccessoryClick
    }

    /// Screen-space point `PopoverWindowController` should anchor to — the
    /// calendar badge's own visual center, accounting for
    /// `NSStatusBarButton`'s leading inset and `MenuBarBadgeIcon`'s canvas
    /// margins.
    var screenAnchor: CGPoint? {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return nil }
        let buttonFrameOnScreen = buttonWindow.convertToScreen(button.bounds)
        // The calendar badge is always the leading element of the combined
        // status item image (see `CombinedMenuBarIcon`) — when the
        // right-hand accessory (contextual event text, or the call icon)
        // is showing, the button is much wider than just the badge, and
        // anchoring on the *whole* button's midpoint would visibly point
        // the popover at the middle of the text instead of at the
        // calendar icon someone actually clicked near.
        // `NSStatusBarButton` reserves a few points of its own leading
        // padding before the image actually starts drawing — not
        // accounted for by the icon's own canvas math alone, which is why
        // the plain `totalCanvasWidth / 2` version landed visibly left of
        // the real icon. This is a measured correction, not derived —
        // nudge it further if it's still off.
        let buttonLeadingInset: CGFloat = 4
        let calendarIconMidX = buttonFrameOnScreen.minX + buttonLeadingInset + MenuBarBadgeIcon.totalCanvasWidth / 2
        return CGPoint(x: calendarIconMidX, y: buttonFrameOnScreen.minY)
    }

    /// The status item button's own window — excluded from "click
    /// outside" dismissal by `PopoverWindowController`, since this
    /// button's own action already toggles the popover; closing it first
    /// would make that click reopen it instead of closing it.
    var buttonWindow: NSWindow? { statusItem?.button?.window }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
            return
        }

        // Calendar and accessory share one status-button action. Only a
        // joinable event makes the accessory region behave as Join.
        if let onAccessoryClick, let accessoryRegionMinX, let button = statusItem?.button {
            let location = button.convert(event.locationInWindow, from: nil)
            let imageWidth = button.image?.size.width ?? button.bounds.width
            let imageOriginX = max(0, (button.bounds.width - imageWidth) / 2)
            if location.x >= imageOriginX + accessoryRegionMinX {
                onAccessoryClick()
                return
            }
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
    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
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

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func menuItem(for row: StatusMenuItem) -> NSMenuItem {
        let item = NSMenuItem(title: row.title, action: #selector(chooseRow(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = RowBox(row)
        // The title says it; AppKit sizes, tints and highlights the symbol.
        if let symbol = row.symbolName { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
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
