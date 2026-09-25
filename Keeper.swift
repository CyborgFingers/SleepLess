import AppKit
import IOKit.pwr_mgt

/// Everything the panel edits, persisted as one blob.
/// ponytail: a schema change that fails to decode just resets to defaults; add per-key migration if that ever bites.
struct Settings: Codable, Equatable {
    var screenOn = false            // keep screen awake (lid open)
    var dims = false                // when idle: dim instead of staying the same
    var level = 0.2                 // dim-to brightness, 0...1
    var delay = 60                  // idle seconds before dimming; 0 = right away
    var lidOn = false               // keep awake with lid closed (Lidless mode)
    var onlyWhileCharging = false   // lid-mode safety, same defaults as Lidless
    var pauseWhenHot = true
    var batteryCutoff = 20          // %, 0 = never
    var autoWhenCharging = false
    var offAfter = 0                // minutes, 0 = no limit
    var offAt: Date?                // pending auto-off
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
    @Published var s: Settings { didSet { if s != oldValue { save(); tick() } } }
    @Published private(set) var battery: Power.Battery?
    @Published private(set) var lidActive = false   // SleepDisabled is really set
    @Published var note: String?                      // why something turned off / failed
    @Published private(set) var helperReady = LidHelper.isReady
    @Published private(set) var helperUpdating = false   // the installed helper is taking this build's signed files (no prompt)
    @Published var setupLater = false                     // "Later" on the setup card, for this launch
    /// The helper is there but from another version: a signed update, or the setup card.
    var helperStale: Bool { !helperReady && LidHelper.isInstalled }
    /// Turn the MagSafe charging light off while the lid is shut (own key: a new Settings field would reset settings).
    @Published var lightOffWithLid = UserDefaults.standard.object(forKey: "lightOffWithLid") as? Bool ?? true {
        didSet { UserDefaults.standard.set(lightOffWithLid, forKey: "lightOffWithLid"); tick() }
    }
    /// We turned the light off and still owe macOS its normal colour (persisted across relaunches).
    private var lightOff = UserDefaults.standard.bool(forKey: "lightIsOff") {
        didSet { UserDefaults.standard.set(lightOff, forKey: "lightIsOff") }
    }
    let icon = MenuIcon()

    private var assertions: [IOPMAssertionID] = []
    private var dimmedFrom: Float?   // brightness before dimming; non-nil = currently dimmed
    private var dimmedTo: Float?
    private var lastRequest: (on: Bool, at: Date)?
    private var lastOnAC: Bool?
    private var keyboardWhileOpen: KeyboardLight.Level?
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

    func setOffAfter(_ minutes: Int) {
        s.offAfter = minutes
        s.offAt = nil   // re-arm from now
    }

    func setAutoWhenCharging(_ on: Bool) {
        lastOnAC = nil   // act on the current power state straight away
        s.autoWhenCharging = on
    }

    func setLoginItem(_ on: Bool) {
        note = LoginItem.set(on)
        objectWillChange.send()
    }

    // MARK: Menu-bar tap (also the panel's main switch)

    /// Pure so --selftest can check it: something on → everything off, remembering what was on;
    /// everything off → the remembered modes (screen awake by default).
    nonisolated static func tapPlan(screenOn: Bool, lidOn: Bool, remembered: TapRestore) -> (screen: Bool, lid: Bool, remember: TapRestore) {
        if screenOn || lidOn { return (false, false, TapRestore(screen: screenOn, lid: lidOn)) }
        return (remembered.screen, remembered.lid, remembered)
    }

    func toggleAwake() {
        let plan = Self.tapPlan(screenOn: s.screenOn, lidOn: s.lidOn, remembered: tapRestore)
        tapRestore = plan.remember
        s.screenOn = plan.screen
        if plan.lid != s.lidOn { setLid(plan.lid) }   // the safety checks and notes still apply
    }

    // ponytail: its own key, not a Settings field — a new field would stop the stored JSON decoding and reset settings
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

        var n = s
        let onAC = battery?.onAC ?? true
        // Auto-enable follows plug/unplug edges only, so a manual flip sticks until the next one.
        if n.autoWhenCharging, onAC != lastOnAC { n.lidOn = onAC && helperReady }
        lastOnAC = onAC
        if n.lidOn, let why = lidBlocker(battery) { n.lidOn = false; note = "Lid-closed mode turned off: \(why)." }
        if n.lidOn, !helperReady, !helperUpdating { n.lidOn = false; note = "Lid-closed mode is off until its helper is set up — click Set up." }

        if !(n.screenOn || n.lidOn) || n.offAfter == 0 {
            n.offAt = nil
        } else if let offAt = n.offAt, now >= offAt {
            n.screenOn = false
            n.lidOn = false
            n.offAt = nil
            note = "Timer finished, normal sleep is back."
        } else if n.offAt == nil {
            n.offAt = now.addingTimeInterval(TimeInterval(n.offAfter * 60))
        }
        if n != s { s = n; return }   // didSet re-runs tick with the settled settings

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
        applyAwake(s.screenOn || darkLid)
        if darkLid { restoreBrightness(); goDark() } else { comeBack(); applyDim() }
        // macOS zeroes the keyboard backlight the moment the lid shuts, before our next tick sees it — so the
        // level to restore is the last one read while the lid was still open.
        if !lidClosed { keyboardWhileOpen = KeyboardLight.get() }
        icon.setLidShut(darkLid)
        applyLid(now)
        icon.show(screen: s.screenOn, lid: s.lidOn)
    }

    private func lidBlocker(_ battery: Power.Battery?) -> String? {
        if s.pauseWhenHot && Power.isHot { return "the Mac is running hot" }
        guard let battery, !battery.onAC else { return nil }
        if s.onlyWhileCharging { return "not on the charger" }
        if s.batteryCutoff > 0 && battery.percent <= s.batteryCutoff { return "battery at \(battery.percent)%" }
        return nil
    }

    private func applyAwake(_ on: Bool) {
        if on, assertions.isEmpty {
            assertions = Awake.hold()
        } else if !on {
            assertions.forEach { IOPMAssertionRelease($0) }
            assertions = []
        }
    }

    private func applyDim() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        guard s.screenOn, s.dims, idle >= Double(s.delay) else { return restoreBrightness() }
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
