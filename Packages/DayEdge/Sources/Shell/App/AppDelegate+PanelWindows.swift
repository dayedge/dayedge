import SwiftUI
import AppKit
import UI

extension AppDelegate {
    /// The panel: the root view in its themed host, in the popover window.
    func makePopoverWindow() -> PopoverWindowController {
        let rootView = RootView(
            models: panelModels,
            presentationStyle: presentationStyle,
            indexActivity: indexActivity,
            commandPresentation: commandPresentation,
            onOpenSettings: { [weak self] destination in self?.showSettings(destination) }
        )
        let hosting = NSHostingController(rootView: ThemedRoot(content: rootView, appearance: appearance))
        // The panel's size is the window's (`PopoverWindowController` fixes
        // the width and the height range). Without this the hosting view
        // re-measures the whole UI for its min/ideal/max size whenever
        // anything inside changes — on every scroll frame (measured).
        hosting.sizingOptions = []

        let popoverWindow = PopoverWindowController(
            contentViewController: hosting,
            presentationStyle: presentationStyle,
            size: .popover(pointerHeight: presentationStyle.pointer?.height ?? 0),
            presentationCoordinator: presentationCoordinator
        )
        return popoverWindow
    }

    /// The Command Window: the same panel models in the wide layout,
    /// centred on the screen under the pointer.
    private func makeCommandWindow() -> PopoverWindowController {
        let rootView = CommandRootView(
            models: panelModels,
            presentation: commandPresentation,
            indexActivity: indexActivity,
            onOpenSettings: { [weak self] destination in self?.showSettings(destination) },
            onClose: { [weak self] in self?.commandWindow?.hide() }
        )
        let hosting = NSHostingController(rootView: ThemedRoot(content: rootView, appearance: appearance))
        hosting.sizingOptions = [] // As the popover's (see `makePopoverWindow`).
        return PopoverWindowController(
            contentViewController: hosting,
            presentationStyle: .standalone,
            size: .commandWindow,
            presentationCoordinator: presentationCoordinator,
            hostPresentation: commandPresentation
        )
    }

    /// ⌃⌥D: shows the Command Window (hiding the popover), or hides it.
    func toggleCommandWindow() {
        let commandWindow = commandWindow ?? makeCommandWindow()
        self.commandWindow = commandWindow
        if commandWindow.isVisible {
            commandWindow.hide()
            return
        }
        popoverWindow?.hide()
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        commandWindow.show(.centered(screen))
    }
}
