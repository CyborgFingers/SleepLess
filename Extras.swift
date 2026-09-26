import AppKit
import Carbon.HIToolbox
import UserNotifications

// Small, mostly pure pieces behind the 1.3 features: clock arithmetic for the timer, the sleepless:// commands,
// the global keyboard shortcut and notifications. Everything without a side effect is checked by --selftest.

enum Clock {
    /// The next time of day `minute` (past midnight) comes round after `now`: today if still ahead, else tomorrow.
    /// Calendar does the wall-clock maths, so a DST change in between never shifts it by an hour.
    nonisolated static func next(minute: Int, after now: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: minute / 60, minute: minute % 60, second: 0), matchingPolicy: .nextTime) ?? now
    }

    /// Time left for the menu bar: "1h 12m", "1h", "12m" — never below a minute, so it changes once a minute.
    nonisolated static func short(_ seconds: TimeInterval) -> String {
        let m = max(1, Int((seconds / 60).rounded(.up)))
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    /// A time to suggest for "until a time": the next full hour that is at least half an hour away.
    nonisolated static func suggestedMinute(after now: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: now)
        return ((c.hour! * 60 + c.minute! + 90) / 60 * 60) % 1440
    }

    /// Minutes past midnight ⇄ a Date today, for the time pickers.
    static func minute(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }

    static func date(minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }

    /// "5:30 PM" (or "17:30") in the user's locale.
    static func label(minute: Int) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date(minute: minute))
    }
}

/// `sleepless://on`, `sleepless://on?minutes=30`, `sleepless://on?until=17:30`, `sleepless://off`,
/// `sleepless://toggle`, `sleepless://lid?on=1` — for Shortcuts, Raycast, scripts (`open "sleepless://on?minutes=30"`).
/// An input boundary: the verb and every parameter are whitelisted, values are clamped, anything else is dropped.
enum Command: Equatable {
    case on(minutes: Int?, untilMinute: Int?)
    case off, toggle
    case lid(Bool)

    static let maxMinutes = 24 * 60

    nonisolated static func parse(_ url: URL) -> Command? {
        guard url.scheme?.lowercased() == "sleepless", let verb = url.host?.lowercased(),
              url.path.isEmpty || url.path == "/", url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var params: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            guard params[item.name.lowercased()] == nil else { return nil }   // a repeated key is not a request we understand
            params[item.name.lowercased()] = item.value ?? ""
        }
        switch (verb, params.count) {
        case ("off", 0): return .off
        case ("toggle", 0): return .toggle
        case ("on", 0): return .on(minutes: nil, untilMinute: nil)
        case ("on", 1):
            if let text = params["minutes"] { return Int(text).flatMap { $0 > 0 ? .on(minutes: min($0, maxMinutes), untilMinute: nil) : nil } }
            if let text = params["until"] { return minute(text).map { .on(minutes: nil, untilMinute: $0) } }
            return nil
        case ("lid", 1):
            switch params["on"] {
            case "1", "true", "yes": return .lid(true)
            case "0", "false", "no": return .lid(false)
            default: return nil
            }
        default: return nil
        }
    }

    /// "17:30" or "7:05" (24-hour) as minutes past midnight.
    private nonisolated static func minute(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count == 2, (1...2).contains(parts[0].count),
              let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }
}

/// A recorded global shortcut. `modifiers` are Carbon's (cmdKey…), ready for RegisterEventHotKey; `key` is what the
/// panel shows for the key ("S", "F5", "↑").
struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    private static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
    private static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    /// From a key press while recording: ⌘, ⌃ or ⌥ plus a key, or a function key on its own. Plain keys (and
    /// shift alone) are refused, so a shortcut can never swallow ordinary typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !flags.isDisjoint(with: [.command, .control, .option]) || Self.functionKeys.contains(event.keyCode) else { return nil }
        guard let key = Self.special[event.keyCode] ?? event.charactersIgnoringModifiers.flatMap({ $0.isEmpty ? nil : $0.uppercased() }) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: Self.carbon(flags), key: key)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    nonisolated static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    /// "⌃⌥⌘S", in the order macOS shows modifiers.
    var label: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }
}

/// The one global shortcut, through Carbon's RegisterEventHotKey: system-wide, no Accessibility permission, no
/// event tap. Pressing it does what a click on the menu-bar icon does.
@MainActor enum HotKeys {
    static var action: () -> Void = {}
    static var recording = false   // the panel is capturing a key press: Esc cancels that, not the panel
    private static var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    /// False when macOS refuses the combination (another app or the system already owns it).
    @discardableResult static func register(_ key: HotKey?) -> Bool {
        if let ref { UnregisterEventHotKey(ref); Self.ref = nil }
        guard let key else { return true }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                MainActor.assumeIsolated { HotKeys.action() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x534C_5353), id: 1)   // 'SLSS'
        let rc = RegisterEventHotKey(key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if rc != noErr { NSLog("SleepLess: hot key \(key.label) refused (\(rc))"); ref = nil }
        return rc == noErr
    }
}

/// Notifications for things that happen while the panel is closed: a timer ending, a safety rule turning lid-closed
/// mode off. Only when the user turns them on — macOS asks for permission at that moment, never before.
enum Notify {
    static func enable(_ done: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { done(granted) } }
        }
    }

    static func post(_ title: String, _ body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
