import AppKit
import IOKit.pwr_mgt

/// Everything the panel edits, persisted as one blob. Decoding fills in any key that is missing, so a blob from
/// an earlier (or later) version keeps every setting it has and takes the defaults for the rest — a new field
/// never resets anyone's settings.
struct Settings: Codable, Equatable {
    var screenOn = false            // keep awake, lid open
    var dims = false                // when idle: dim instead of staying the same
    var level = 0.2                 // dim-to brightness, 0...1
    var delay = 60                  // idle seconds before dimming; 0 = right away
    var lidOn = false               // keep awake with lid closed
    var onlyWhileCharging = false   // lid-mode safety
    var pauseWhenHot = true
    var batteryCutoff = 20          // %, 0 = never
    var autoWhenCharging = false
    var offAfter = 0                // minutes, 0 = no limit
    var offAt: Date?                // pending auto-off
    // 1.3
    var screenSleeps = false        // when idle: the screen may sleep, the Mac stays awake
    var offAtMinute: Int?           // turn off at a time of day (minutes past midnight) instead of after `offAfter`
    var offFrom: Date?              // when the pending auto-off was armed (the progress bar's start)
    var appsOn = false              // automations: keep awake while one of `apps` is running…
    var apps: [AppRef] = []
    var powerOn = false             // …on the power adapter…
    var displayOn = false           // …with an external display connected…
    var scheduleOn = false          // …on a schedule
    var days = Schedule.weekdays    // bitmask by Calendar weekday (1 = Sunday)
    var from = 9 * 60               // schedule window, minutes past midnight; to <= from runs overnight
    var to = 17 * 60
    var timeInMenuBar = false       // time left beside the menu-bar icon while a timer runs
    var notify = false              // notifications when a timer ends or a safety rule turns something off
    var hotKey: HotKey?             // global keyboard shortcut = a click on the icon

    init() {}

    /// Every key optional; a wrong type counts as missing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        screenOn = get(.screenOn, screenOn)
        dims = get(.dims, dims)
        level = get(.level, level)
        delay = get(.delay, delay)
        lidOn = get(.lidOn, lidOn)
        onlyWhileCharging = get(.onlyWhileCharging, onlyWhileCharging)
        pauseWhenHot = get(.pauseWhenHot, pauseWhenHot)
        batteryCutoff = get(.batteryCutoff, batteryCutoff)
        autoWhenCharging = get(.autoWhenCharging, autoWhenCharging)
        offAfter = get(.offAfter, offAfter)
        offAt = try? c.decodeIfPresent(Date.self, forKey: .offAt)
        screenSleeps = get(.screenSleeps, screenSleeps)
        offAtMinute = try? c.decodeIfPresent(Int.self, forKey: .offAtMinute)
        offFrom = try? c.decodeIfPresent(Date.self, forKey: .offFrom)
        appsOn = get(.appsOn, appsOn)
        apps = get(.apps, apps)
        powerOn = get(.powerOn, powerOn)
        displayOn = get(.displayOn, displayOn)
        scheduleOn = get(.scheduleOn, scheduleOn)
        days = get(.days, days)
        from = get(.from, from)
        to = get(.to, to)
        timeInMenuBar = get(.timeInMenuBar, timeInMenuBar)
        notify = get(.notify, notify)
        hotKey = try? c.decodeIfPresent(HotKey.self, forKey: .hotKey)
    }

    /// A timer is set (a duration or a time of day).
    var hasTimer: Bool { offAfter > 0 || offAtMinute != nil }
}

/// The modes a menu-bar tap turns back on: whatever was on when the last tap turned SleepLess off.
struct TapRestore: Codable, Equatable {
    var screen = true
    var lid = false
}

/// Screen and keyboard-light levels from before the lid was shut.
struct LidDark: Codable, Equatable {
    var screen: Float?
    var keyboard: KeyboardLight.Level?
}

/// One reconcile loop: every second (and on every settings change) it makes the Mac match `s`.
@MainActor final class Keeper: ObservableObject {
    @Published var s: Settings {
        didSet {
            guard s != oldValue else { return }
            save()
            if s.hotKey != oldValue.hotKey { HotKeys.register(s.hotKey) }
            tick()
        }
    }
    @Published private(set) var battery: Power.Battery?
    @Published private(set) var lidActive = false   // SleepDisabled is really set
    @Published var note: String?                      // why something turned off / failed
    @Published private(set) var reasons: [Reason] = []   // automations keeping the Mac awake right now
    @Published private(set) var paused: [Reason] = []    // automations a click turned off, until their reason ends
    @Published private(set) var menuTitle = ""           // time left beside the menu-bar icon (Settings.timeInMenuBar)
    @Published private(set) var helperReady = LidHelper.isReady
    @Published private(set) var helperUpdating = false   // the installed helper is taking this build's signed files (no prompt)
    @Published var setupLater = false                     // "Later" on the setup card, for this launch
    /// The helper is there but from another version: a signed update, or the setup card.
    var helperStale: Bool { !helperReady && LidHelper.isInstalled }
    /// Turn the MagSafe charging light off while the lid is shut (own key from before Settings could grow).
    @Published var lightOffWithLid = UserDefaults.standard.object(forKey: "lightOffWithLid") as? Bool ?? true {
        didSet { UserDefaults.standard.set(lightOffWithLid, forKey: "lightOffWithLid"); tick() }
    }
    /// We turned the light off and still owe macOS its normal colour (persisted across relaunches).
    private var lightOff = UserDefaults.standard.bool(forKey: "lightIsOff") {
        didSet { UserDefaults.standard.set(lightOff, forKey: "lightIsOff") }
    }
    let icon = MenuIcon()

    /// On: a mode is on by hand, or an automation holds.
    var isOn: Bool { s.screenOn || s.lidOn || !reasons.isEmpty }

    private var assertions: [IOPMAssertionID] = []
    private var holdingDisplay: Bool?   // nil = no assertions held; else whether the display one is among them
    private var dimmedFrom: Float?   // brightness before dimming; non-nil = currently dimmed
    private var dimmedTo: Float?
    private var lastRequest: (on: Bool, at: Date)?
    private var lastOnAC: Bool?
    private var keyboardWhileOpen: KeyboardLight.Level?
    private var snoozed: Set<Reason> = []   // in memory only: a paused automation comes back once its reason has ended
    private var apps: AppWatch?
    private var timer: Timer?
    /// Levels to restore when the lid opens. Persisted, so a crash or quit with the lid shut can't leave the
    /// screen at 0: the next tick (lid open) puts them back.
    private var lidDark = UserDefaults.standard.data(forKey: "lidDark").flatMap { try? JSONDecoder().decode(LidDark.self, from: $0) } {
        didSet { UserDefaults.standard.set(lidDark.flatMap { try? JSONEncoder().encode($0) }, forKey: "lidDark") }
    }
    private static let heartbeat: TimeInterval = 30   // the helper treats > 90 s as a dead app

    init() {
        s = UserDefaults.standard.data(forKey: "settings").flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        if !UserDefaults.standard.bool(forKey: "loginItemOffered") {   // asked-for default: start at login
            UserDefaults.standard.set(true, forKey: "loginItemOffered")
            note = LoginItem.set(true)
        }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { self.tick() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.shutdown() }
        }
        // The automations' event sources: apps starting and quitting, displays coming and going. Power is read each tick.
        let apps = AppWatch()
        apps.changed = { [weak self] in self?.tick() }
        self.apps = apps
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        HotKeys.action = { [weak self] in self?.toggleAwake() }
        HotKeys.register(s.hotKey)
        if helperStale {   // an app update changed the helper: the installed one takes the signed files itself
            helperUpdating = true
            HelperUpdate.request(ready: { LidHelper.isReady }) { _ in
                self.helperUpdating = false
                self.helperReady = LidHelper.isReady
                self.tick()
            }
        }
        tick()
    }

    /// --shots: sample state for the panel — no timer, no tick, nothing on the Mac touched.
    init(shots s: Settings, battery: Power.Battery?, helperReady: Bool, lidActive: Bool = false, note: String? = nil, reasons: [Reason] = []) {
        self.s = s
        self.battery = battery
        self.helperReady = helperReady
        self.lidActive = lidActive
        self.note = note
        self.reasons = reasons
        icon.show(screen: s.screenOn || !reasons.isEmpty, lid: s.lidOn)
    }

    // MARK: User actions that need more than a plain binding

    /// The one administrator prompt (password or Touch ID): the setup card, a Set up… button, or Reinstall helper.
    func setUpHelper() {
        note = nil
        switch LidHelper.install() {
        case .done: helperReady = true
        case .cancelled: break
        case .failed(let why): note = why
        }
        tick()
    }

    func setLid(_ on: Bool) {
        note = nil
        guard on else { s.lidOn = false; return }
        if let why = lidBlocker(Power.battery()) { note = "Can't keep awake with lid closed: \(why)."; return }
        guard helperReady else { note = "Lid-closed mode needs the one-time setup — click Set up."; return }
        s.lidOn = true
    }

    /// One settings change, one save and one tick.
    private func edit(_ change: (inout Settings) -> Void) {
        var n = s
        change(&n)
        s = n
    }

    /// The timer: a duration (0 = never) or a time of day. Either restarts the countdown.
    func setOffAfter(_ minutes: Int) {
        edit { $0.offAfter = minutes; $0.offAtMinute = nil; $0.offAt = nil; $0.offFrom = nil }
    }

    func setOffAt(minute: Int) {
        edit { $0.offAtMinute = minute; $0.offAt = nil; $0.offFrom = nil }
    }

    /// The quick durations (menu, sleepless://on?minutes=): the timer, and SleepLess on if it isn't already.
    func keepAwake(minutes: Int) {
        setOffAfter(minutes)
        if !(s.screenOn || s.lidOn) { turnOn() }
    }

    func keepAwake(untilMinute: Int) {
        setOffAt(minute: untilMinute)
        if !(s.screenOn || s.lidOn) { turnOn() }
    }

    func setAutoWhenCharging(_ on: Bool) {
        lastOnAC = nil   // act on the current power state straight away
        s.autoWhenCharging = on
    }

    func setLoginItem(_ on: Bool) {
        note = LoginItem.set(on)
        objectWillChange.send()
    }

    /// Turning notifications on asks macOS for permission, right then; a refusal leaves the switch off.
    func setNotify(_ on: Bool) {
        guard on else { s.notify = false; return }
        Notify.enable { [weak self] granted in
            self?.s.notify = granted
            if !granted { self?.note = "Notifications are off for SleepLess in System Settings › Notifications." }
        }
    }

    /// A sleepless:// command, already validated by Command.parse.
    func handle(_ command: Command) {
        switch command {
        case .on(let minutes, let untilMinute):
            if let minutes { setOffAfter(minutes) } else if let untilMinute { setOffAt(minute: untilMinute) }
            if !(s.screenOn || s.lidOn) { turnOn() }
        case .off: turnOff()
        case .toggle: toggleAwake()
        case .lid(let on): setLid(on)
        }
    }

    // MARK: Menu-bar tap (also the panel's main switch and the keyboard shortcut)

    /// Pure so --selftest can check it: something on → everything off, remembering what was on;
    /// everything off → the remembered modes (screen awake by default).
    nonisolated static func tapPlan(screenOn: Bool, lidOn: Bool, remembered: TapRestore) -> (screen: Bool, lid: Bool, remember: TapRestore) {
        if screenOn || lidOn { return (false, false, TapRestore(screen: screenOn, lid: lidOn)) }
        return (remembered.screen, remembered.lid, remembered)
    }

    func toggleAwake() { isOn ? turnOff() : turnOn() }

    /// The remembered modes back on.
    func turnOn() {
        let plan = Self.tapPlan(screenOn: false, lidOn: false, remembered: tapRestore)
        s.screenOn = plan.screen
        if plan.lid != s.lidOn { setLid(plan.lid) }   // the safety checks and notes still apply
    }

    /// Everything off. An automation that is holding is paused until its reason ends (the app quits, the charger
    /// comes out, the window closes) — otherwise a click could never win against it.
    func turnOff() {
        if s.screenOn || s.lidOn {
            let plan = Self.tapPlan(screenOn: s.screenOn, lidOn: s.lidOn, remembered: tapRestore)
            tapRestore = plan.remember
            s.screenOn = false
            if s.lidOn { setLid(false) }
        }
        if !reasons.isEmpty {
            snoozed.formUnion(reasons)
            tick()
        }
    }

    // ponytail: its own key from before Settings could grow — left where it is
    private var tapRestore: TapRestore {
        get { UserDefaults.standard.data(forKey: "tapRestores").flatMap { try? JSONDecoder().decode(TapRestore.self, from: $0) } ?? TapRestore() }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "tapRestores") }
    }

    // MARK: Reconcile

    private func tick() {
        let now = Date()
        let battery = Power.battery()
        if battery != self.battery { self.battery = battery }
        let active = Power.sleepDisabled
        if active != lidActive { lidActive = active }
        let onAC = battery?.onAC ?? true

        // Automations: the rules that hold right now, minus the ones a click paused (a pause ends with its reason).
        let live = Automation.reasons(s, running: apps?.running ?? [], onAC: onAC, externalDisplay: Display.hasExternal, now: now)
        snoozed = snoozed.filter(live.contains)
        let reasons = live.filter { !snoozed.contains($0) }
        if reasons != self.reasons { self.reasons = reasons }
        let paused = live.filter(snoozed.contains)
        if paused != self.paused { self.paused = paused }

        var n = s
        // Auto-enable follows plug/unplug edges only, so a manual flip sticks until the next one.
        if n.autoWhenCharging, onAC != lastOnAC { n.lidOn = onAC && helperReady }
        lastOnAC = onAC
        if n.lidOn, let why = lidBlocker(battery) {
            n.lidOn = false
            note = "Lid-closed mode turned off: \(why)."
            if s.notify { Notify.post("Lid-closed mode turned off", "SleepLess stopped it: \(why).") }
        }
        if n.lidOn, !helperReady, !helperUpdating { n.lidOn = false; note = "Lid-closed mode is off until its helper is set up — click Set up." }

        // The timer runs against the modes turned on by hand; automations keep their own hours.
        if !(n.screenOn || n.lidOn) || !n.hasTimer {
            n.offAt = nil
            n.offFrom = nil
        } else if let offAt = n.offAt, now >= offAt {
            n.screenOn = false
            n.lidOn = false
            n.offAt = nil
            n.offFrom = nil
            note = "Timer finished, normal sleep is back."
            if s.notify { Notify.post("SleepLess timer finished", "Your Mac sleeps normally again.") }
        } else if n.offAt == nil {
            n.offFrom = now
            n.offAt = n.offAtMinute.map { Clock.next(minute: $0, after: now) } ?? now.addingTimeInterval(TimeInterval(n.offAfter * 60))
        }
        if n != s { s = n; return }   // didSet re-runs tick with the settled settings

        let title = s.timeInMenuBar ? s.offAt.map { Clock.short($0.timeIntervalSince(now)) } ?? "" : ""
        if title != menuTitle { menuTitle = title }

        // Lid shut while the Mac is kept up: screen and keyboard light go to 0 but the display stays technically
        // awake — a sleeping display trips the "require password" lock, a dark one doesn't, so opening the lid
        // lands straight back in the session. With a monitor plugged in it's ordinary clamshell use: hands off.
        let lidClosed = Power.lidClosed
        let darkLid = lidClosed && lidActive && !Display.hasExternal
        // MagSafe light off while the lid is shut in lid-closed mode, macOS's normal colour again when it opens.
        // Only on the change, so it never fights macOS (or JuiceLeft, which drives the light while the lid is open).
        let wantLightOff = lightOffWithLid && lidClosed && lidActive
        if helperReady, wantLightOff != lightOff {
            LidHelper.light(!wantLightOff)
            lightOff = wantLightOff
        }
        // Awake by hand or by an automation, with the screen kept on unless "Sleeps" is chosen; a dark lid needs the
        // display assertion whatever the choice (see above).
        let awake = s.screenOn || !reasons.isEmpty
        applyAwake(awake || darkLid, display: (awake && !s.screenSleeps) || darkLid)
        if darkLid { restoreBrightness(); goDark() } else { comeBack(); applyDim(awake) }
        // macOS zeroes the keyboard backlight the moment the lid shuts, before our next tick sees it — so the
        // level to restore is the last one read while the lid was still open.
        if !lidClosed { keyboardWhileOpen = KeyboardLight.get() }
        icon.setLidShut(darkLid)
        applyLid(now)
        icon.show(screen: awake, lid: s.lidOn)
    }

    private func lidBlocker(_ battery: Power.Battery?) -> String? {
        if s.pauseWhenHot && Power.isHot { return "the Mac is running hot" }
        guard let battery, !battery.onAC else { return nil }
        if s.onlyWhileCharging { return "not on the charger" }
        if s.batteryCutoff > 0 && battery.percent <= s.batteryCutoff { return "battery at \(battery.percent)%" }
        return nil
    }

    private func applyAwake(_ on: Bool, display: Bool) {
        let want: Bool? = on ? display : nil
        guard want != holdingDisplay else { return }
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions = want.map { Awake.hold(display: $0) } ?? []
        holdingDisplay = want
    }

    private func applyDim(_ awake: Bool) {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        guard awake, s.dims, !s.screenSleeps, idle >= Double(s.delay) else { return restoreBrightness() }
        guard let original = dimmedFrom ?? Brightness.get() else { return }
        let target = min(original, Float(s.level))   // never brighten a screen that's already below the target
        guard target != dimmedTo else { return }        // re-applies live while the slider moves
        dimmedFrom = original
        dimmedTo = target
        Brightness.set(target)
    }

    /// Saves the screen and keyboard-light levels once, then holds both at 0 — re-applied every tick because
    /// ambient-light adjustment would otherwise creep them back up.
    private func goDark() {
        if lidDark == nil { lidDark = LidDark(screen: Brightness.get(), keyboard: keyboardWhileOpen ?? KeyboardLight.get()) }
        if (Brightness.get() ?? 0) > 0 { Brightness.set(0) }
        if let keyboard = KeyboardLight.get(), keyboard.brightness > 0 || keyboard.auto {
            KeyboardLight.set(.init(brightness: 0, auto: false))
        }
    }

    private func comeBack() {
        guard let saved = lidDark else { return }
        if let screen = saved.screen { Brightness.set(screen) }
        if let keyboard = saved.keyboard { KeyboardLight.set(keyboard) }
        lidDark = nil
    }

    private func restoreBrightness() {
        guard let dimmedFrom else { return }
        Brightness.set(dimmedFrom)
        self.dimmedFrom = nil
        dimmedTo = nil
    }

    private func applyLid(_ now: Date) {
        guard helperReady else { return }
        let on = s.lidOn
        if let last = lastRequest, last.on == on, !on || now.timeIntervalSince(last.at) < Self.heartbeat { return }
        LidHelper.request(on)
        lastRequest = (on, now)
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(s), forKey: "settings")
    }

    private func shutdown() {
        restoreBrightness()
        comeBack()
        if helperReady, lightOff { LidHelper.light(true); lightOff = false }
        if helperReady, s.lidOn { LidHelper.request(false) }   // settings stay on, so it resumes next launch
    }
}
