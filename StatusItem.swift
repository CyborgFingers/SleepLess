import AppKit
import Combine
import SwiftUI

/// The menu-bar item. A click turns SleepLess on or off; press and hold opens the settings popover (closed by Esc,
/// a click anywhere else, or another click on the icon); right-click / ⌃-click opens the quick menu (StatusMenu).
/// While a timer runs, the time left can sit beside the icon. Opening the app again shows the panel too — in a
/// floating panel at the top right when a full menu bar has hidden the icon (under the notch, or off the edge).
@MainActor final class StatusItemController {
    enum Gesture: Equatable { case tap, hold, menu }
    static let holdDelay: TimeInterval = 0.35

    /// The click decision, kept pure so --selftest can check it: right- or ⌃-click opens the menu; a left press
    /// is a tap if the button comes up before the hold delay, otherwise a hold.
    nonisolated static func gesture(_ type: NSEvent.EventType, control: Bool, releasedInTime: () -> Bool) -> Gesture {
        if type == .rightMouseDown || control { return .menu }
        return releasedInTime() ? .tap : .hold
    }

    /// Whether the menu bar has hidden the icon, kept pure so --selftest can check it: a full menu bar pushes
    /// status items under the camera notch or off the edge of the screen. `item` is the icon's window frame (nil
    /// without one), `notch` the gap between the screen's two menu-bar strips (nil without a notch), `visible`
    /// whether macOS reports the window on screen.
    nonisolated static func iconHidden(item: CGRect?, screen: CGRect, notch: CGRect?, visible: Bool) -> Bool {
        guard let item, visible else { return true }
        if let notch, item.maxX > notch.minX, item.minX < notch.maxX { return true }
        return item.minX < screen.minX || item.maxX > screen.maxX
    }

    private let keeper: Keeper
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let host: NSHostingController<AnyView>
    private var menu: StatusMenu?
    private var floating: NSPanel?       // the panel shown when the icon can't be reached
    private var anchor: Any?             // keeps the floating panel's top-right corner put as it grows
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
        guard popover.isShown || floating != nil else { return false }
        if event.type == .keyDown {
            guard event.keyCode == 53, !HotKeys.recording else { return false }   // Esc while recording a shortcut cancels that instead
            close()
            return true
        }
        let own: [NSWindow?] = [host.view.window, item.button?.window, floating]
        if !own.contains(where: { $0 === event.window }) { close() }
        return false
    }

    /// The app was opened again (from Applications, Spotlight, `open -a`): the panel, one way or the other.
    func reopen() {
        guard !popover.isShown, floating == nil else { return }
        if iconIsHidden { showFloating() } else { open() }
    }

    private var iconIsHidden: Bool {
        guard let window = item.button?.window, let screen = window.screen ?? NSScreen.screens.first else { return true }
        var notch: CGRect?
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = CGRect(x: left.maxX, y: left.minY, width: right.minX - left.maxX, height: left.height)
        }
        return Self.iconHidden(item: window.frame, screen: screen.frame, notch: notch, visible: window.occlusionState.contains(.visible))
    }

    /// The same panel in a small floating window at the top right of the menu bar's screen, with a note about the
    /// full menu bar. It takes key presses without activating the app, and Esc or a click anywhere else closes it.
    private func showFloating() {
        guard let screen = item.button?.window?.screen ?? NSScreen.screens.first else { return }
        let card = AnyView(Self.panel(keeper, visible: true, iconHidden: true)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12))))
        let host = NSHostingController(rootView: card)
        host.sizingOptions = .preferredContentSize
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: host.view.fittingSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentViewController = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let corner = NSPoint(x: screen.visibleFrame.maxX - 12, y: screen.visibleFrame.maxY - 8)   // just under the menu bar
        panel.setFrameOrigin(NSPoint(x: corner.x - panel.frame.width, y: corner.y - panel.frame.height))
        anchor = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { panel.setFrameOrigin(NSPoint(x: corner.x - panel.frame.width, y: corner.y - panel.frame.height)) }
        }
        floating = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private final class FloatingPanel: NSPanel { override var canBecomeKey: Bool { true } }

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

    private static func panel(_ keeper: Keeper, visible: Bool, iconHidden: Bool = false) -> AnyView {
        AnyView(Panel(keeper: keeper, iconHidden: iconHidden).environment(\.panelVisible, visible))
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
        if let floating {
            floating.orderOut(nil)
            self.floating = nil
            if let anchor { NotificationCenter.default.removeObserver(anchor) }
            anchor = nil
        }
        guard popover.isShown else { return }
        popover.close()
        host.rootView = Self.panel(keeper, visible: false)
    }
}
