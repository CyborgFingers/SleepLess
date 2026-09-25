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

/// One reconcile loop: every second (and on every settings change) it makes the Mac match `s`.
@MainActor final class Keeper: ObservableObject {
    @Published var s: Settings { didSet { if s != oldValue { save(); tick() } } }
    @Published private(set) var battery: Power.Battery?
    @Published private(set) var lidActive = false   // SleepDisabled is really set
    @Published var note: String?                      // why something turned off / failed
    @Published private(set) var helperReady = LidHelper.isReady
    let icon = MenuIcon()

    private var assertions: [IOPMAssertionID] = []
    private var dimmedFrom: Float?   // brightness before dimming; non-nil = currently dimmed
    private var dimmedTo: Float?
    private var lastRequest: (on: Bool, at: Date)?
    private var lastOnAC: Bool?
    private var timer: Timer?
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
        tick()
    }

    // MARK: User actions that need more than a plain binding

    func setLid(_ on: Bool) {
        note = nil
        guard on else { s.lidOn = false; return }
        if let why = lidBlocker(Power.battery()) { note = "Can't keep awake with lid closed: \(why)."; return }
        if !helperReady {
            if let error = LidHelper.install() { note = error; return }
            helperReady = true
        }
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
        if n.lidOn, !helperReady { n.lidOn = false; note = "Lid helper missing. Flip the lid switch to reinstall it." }

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

        applyAwake(s.screenOn)
        applyDim()
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
        if helperReady, s.lidOn { LidHelper.request(false) }   // settings stay on, so it resumes next launch
    }
}
