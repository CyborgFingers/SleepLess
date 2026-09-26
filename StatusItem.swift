import AppKit
import Combine
import SwiftUI

/// The menu-bar item. A click turns SleepLess on or off; press and hold opens the settings popover (closed by Esc,
/// a click anywhere else, or another click on the icon); right-click / ⌃-click opens the quick menu (StatusMenu).
/// While a timer runs, the time left can sit beside the icon.
@MainActor final class StatusItemController {
    enum Gesture: Equatable { case tap, hold, menu }
    static let holdDelay: TimeInterval = 0.35

    /// The click decision, kept pure so --selftest can check it: right- or ⌃-click opens the menu; a left press
    /// is a tap if the button comes up before the hold delay, otherwise a hold.
    nonisolated static func gesture(_ type: NSEvent.EventType, control: Bool, releasedInTime: () -> Bool) -> Gesture {
        if type == .rightMouseDown || control { return .menu }
        return releasedInTime() ? .tap : .hold
    }

    private let keeper: Keeper
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let host: NSHostingController<AnyView>
    private var menu: StatusMenu?
    private var sinks: [AnyCancellable] = []
    private var monitors: [Any] = []

    init(keeper: Keeper) {
        self.keeper = keeper
        host = NSHostingController(rootView: Self.panel(keeper, visible: false))
        host.sizingOptions = .preferredContentSize   // the popover follows the SwiftUI content as it expands
        popover.contentViewController = host
        popover.behavior = .applicationDefined      // closed by the monitors below; .transient races with the icon click

        item.autosaveName = "Item-0"   // what MenuBarExtra used, so menu-bar organisers keep recognising the icon
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.setAccessibilityHelp("Click to turn SleepLess on or off. Press and hold for settings, right-click for the menu.")
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        // The menu comes off the item a moment after it closes: the chosen item's action is sent after menuDidClose,
        // and taking the menu away inside it would drop that action.
        menu = StatusMenu(keeper: keeper, openSettings: { [weak self] in self?.open() },
                          closed: { [weak self] in DispatchQueue.main.async { MainActor.assumeIsolated { self?.item.menu = nil } } })
        // The glyph, with a small dot at its corner while an update waits in the panel.
        keeper.icon.$image.combineLatest(Updater.shared.$state.map { $0 != .idle && Updater.shared.available != nil }.removeDuplicates())
            .sink { image, update in MainActor.assumeIsolated { button.image = update ? Updater.badged(image) : image } }
            .store(in: &sinks)
        keeper.$s.combineLatest(keeper.$reasons).map { $0.screenOn || $0.lidOn || !$1.isEmpty }.removeDuplicates()
            .sink { on in MainActor.assumeIsolated { button.setAccessibilityLabel(on ? "SleepLess: on" : "SleepLess: off") } }
            .store(in: &sinks)
        keeper.$menuTitle.removeDuplicates()
            .sink { title in MainActor.assumeIsolated { button.title = title; button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading } }
            .store(in: &sinks)

        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.sawLocal(event) ?? false }
            return swallow ? nil : event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        monitors = [local, global].compactMap { $0 }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    /// Esc closes the popover (and is swallowed); a click in any window but the popover's or the icon's closes it.
    private func sawLocal(_ event: NSEvent) -> Bool {
        guard popover.isShown else { return false }
        if event.type == .keyDown {
            guard event.keyCode == 53, !HotKeys.recording else { return false }   // Esc while recording a shortcut cancels that instead
            close()
            return true
        }
        if ![host.view.window, item.button?.window].contains(where: { $0 === event.window }) { close() }
        return false
    }

    @objc private func clicked() {
        guard let event = NSApp.currentEvent else { return }
        if popover.isShown { return close() }
        let gesture = Self.gesture(event.type, control: event.modifierFlags.contains(.control)) {
            // Peek (no dequeue) so the button's own tracking still sees the mouse-up.
            NSApp.nextEvent(matching: .leftMouseUp, until: Date(timeIntervalSinceNow: Self.holdDelay), inMode: .eventTracking, dequeue: false) != nil
        }
        switch gesture {
        case .tap: keeper.toggleAwake()
        case .hold: open()
        case .menu: showMenu()
        }
    }

    /// NSStatusItem pops its menu up on a click when it has one — so it gets one for this click only, and the
    /// menu's delegate takes it away again when it closes (the click gesture must keep working).
    private func showMenu() {
        guard let menu, let button = item.button else { return }
        item.menu = menu.menu()
        button.performClick(nil)
    }

    private static func panel(_ keeper: Keeper, visible: Bool) -> AnyView {
        AnyView(Panel(keeper: keeper).environment(\.panelVisible, visible))
    }

    private func open() {
        guard let button = item.button, !popover.isShown else { return }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        host.rootView = Self.panel(keeper, visible: true)
        host.view.layoutSubtreeIfNeeded()
        popover.contentSize = host.view.fittingSize
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        host.view.window?.makeKey()
    }

    private func close() {
        guard popover.isShown else { return }
        popover.close()
        host.rootView = Self.panel(keeper, visible: false)
    }
}
