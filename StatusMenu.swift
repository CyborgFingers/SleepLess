import AppKit

/// The right-click (or ⌃-click) menu on the menu-bar icon: what SleepLess is doing, on/off, the quick durations,
/// and the way to the settings panel. Built fresh each time it opens, so it always shows the current state.
@MainActor final class StatusMenu: NSObject, NSMenuDelegate {
    private let keeper: Keeper
    private let openSettings: () -> Void
    private let closed: () -> Void

    init(keeper: Keeper, openSettings: @escaping () -> Void, closed: @escaping () -> Void) {
        self.keeper = keeper
        self.openSettings = openSettings
        self.closed = closed
    }

    func menu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let s = keeper.s

        var status = keeper.isOn ? "Keeping your Mac awake" : "Your Mac sleeps normally"
        if s.screenOn || s.lidOn, let offAt = s.offAt, offAt > .now { status += " · \(Clock.short(offAt.timeIntervalSinceNow)) left" }
        if !keeper.reasons.isEmpty { status += " · " + Automation.sentence(keeper.reasons, prefix: "while ") }
        let title = menu.addItem(withTitle: status, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(item(keeper.isOn ? "Turn Off" : "Turn On", #selector(toggle), help: "The same as a click on the icon\(s.hotKey.map { " or \($0.label)" } ?? "")."))
        menu.addItem(.separator())

        menu.addItem(header("Keep awake for"))
        let timed = (s.screenOn || s.lidOn) && s.hasTimer
        for (minutes, label) in [(15, "15 minutes"), (30, "30 minutes"), (60, "1 hour"), (120, "2 hours"), (240, "4 hours")] {
            let item = item(label, #selector(keepFor(_:)), tag: minutes, help: "Keep the Mac awake for \(label), then back to normal sleep.")
            item.state = timed && s.offAtMinute == nil && s.offAfter == minutes ? .on : .off
            menu.addItem(item)
        }
        let until = item("Until a time…", #selector(untilTime), help: "Keep the Mac awake until a time you pick in the panel.")
        until.state = timed && s.offAtMinute != nil ? .on : .off
        menu.addItem(until)
        let forever = item("Indefinitely", #selector(indefinitely), help: "Keep the Mac awake until you turn it off.")
        forever.state = (s.screenOn || s.lidOn) && !s.hasTimer ? .on : .off
        menu.addItem(forever)
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(settings), key: ",", help: "The panel: modes, safety rules, automations and more (press and hold the icon does this too)."))
        menu.addItem(item("Quit SleepLess", #selector(quit), key: "q", help: "Brightness and normal sleep come back straight away."))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "", tag: Int = 0, help: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.tag = tag
        item.toolTip = help
        return item
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) { return NSMenuItem.sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggle() { keeper.toggleAwake() }
    @objc private func keepFor(_ sender: NSMenuItem) { keeper.keepAwake(minutes: sender.tag) }
    @objc private func indefinitely() {
        keeper.setOffAfter(0)
        if !(keeper.s.screenOn || keeper.s.lidOn) { keeper.turnOn() }
    }
    @objc private func untilTime() {
        if keeper.s.offAtMinute == nil { keeper.keepAwake(untilMinute: Clock.suggestedMinute(after: Date())) } else if !(keeper.s.screenOn || keeper.s.lidOn) { keeper.turnOn() }
        openSettings()   // the time picker is in the panel
    }
    @objc private func settings() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    func menuDidClose(_ menu: NSMenu) { closed() }
}
