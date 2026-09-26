import Foundation

/// The pure parts behind the timer, automations, the URL scheme and settings migration, run by --selftest.
enum SelfTest {
    static func features() {
        settings()
        clock()
        schedule()
        automations()
        commands()
        hotKeys()
    }

    /// A settings blob exactly as 1.2.1 wrote it must keep every value and take defaults for the new fields;
    /// an empty or partly broken blob must never throw the rest away.
    private static func settings() {
        let old = #"{"screenOn":true,"dims":true,"level":0.35,"delay":120,"lidOn":false,"onlyWhileCharging":true,"pauseWhenHot":false,"batteryCutoff":30,"autoWhenCharging":true,"offAfter":60,"offAt":780000000.5}"#
        let s = try! JSONDecoder().decode(Settings.self, from: old.data(using: .utf8)!)
        precondition(s.screenOn && s.dims && s.level == 0.35 && s.delay == 120 && !s.lidOn && s.onlyWhileCharging && !s.pauseWhenHot
                     && s.batteryCutoff == 30 && s.autoWhenCharging && s.offAfter == 60 && s.offAt == Date(timeIntervalSinceReferenceDate: 780000000.5),
                     "FAIL: 1.2.1 settings not kept: \(s)")
        let fresh = Settings()
        precondition(!s.screenSleeps && s.offAtMinute == nil && s.offFrom == nil && !s.appsOn && s.apps.isEmpty && !s.powerOn && !s.displayOn
                     && !s.scheduleOn && s.days == fresh.days && s.from == fresh.from && s.to == fresh.to && !s.timeInMenuBar && !s.notify && s.hotKey == nil,
                     "FAIL: new settings should take their defaults: \(s)")
        precondition(try! JSONDecoder().decode(Settings.self, from: "{}".data(using: .utf8)!) == fresh, "FAIL: an empty blob should be the defaults")
        let broken = try! JSONDecoder().decode(Settings.self, from: #"{"level":"high","offAfter":30,"apps":5}"#.data(using: .utf8)!)
        precondition(broken.level == fresh.level && broken.offAfter == 30 && broken.apps.isEmpty, "FAIL: a wrong-typed key should count as missing")
        var full = fresh
        full.apps = [AppRef(id: "us.zoom.xos", name: "zoom.us")]
        full.hotKey = HotKey(keyCode: 1, modifiers: 4352, key: "S")
        full.offAtMinute = 17 * 60 + 30
        full.offFrom = Date(timeIntervalSinceReferenceDate: 1)
        let again = try! JSONDecoder().decode(Settings.self, from: try! JSONEncoder().encode(full))
        precondition(again == full, "FAIL: settings should round-trip")
        let newer = try! JSONDecoder().decode(Settings.self, from: #"{"screenOn":true,"somethingFrom2027":[1,2]}"#.data(using: .utf8)!)
        precondition(newer.screenOn, "FAIL: a key from a newer version should be ignored")
    }

    private static var auckland: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        c.locale = Locale(identifier: "en_NZ")
        return c
    }

    private static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// Until-a-time: today if ahead, tomorrow if not, and a DST change in between (NZ springs forward 27 Sep 2026
    /// at 02:00) never adds or drops an hour of wall-clock time.
    private static func clock() {
        let cal = auckland
        let afternoon = date(2026, 9, 24, 17, 0, in: cal)
        precondition(Clock.next(minute: 17 * 60 + 30, after: afternoon) == date(2026, 9, 24, 17, 30, in: cal), "FAIL: 17:30 is later today")
        precondition(Clock.next(minute: 9 * 60, after: afternoon) == date(2026, 9, 25, 9, 0, in: cal), "FAIL: 09:00 is tomorrow")
        precondition(Clock.next(minute: 17 * 60, after: afternoon) == date(2026, 9, 25, 17, 0, in: cal), "FAIL: the current minute means tomorrow")
        let beforeDST = date(2026, 9, 26, 23, 0, in: cal)
        let across = Clock.next(minute: 5 * 60, after: beforeDST)
        precondition(cal.component(.hour, from: across) == 5 && cal.component(.day, from: across) == 27 && across.timeIntervalSince(beforeDST) == 5 * 3600,
                     "FAIL: 05:00 across the DST change should be 5 wall-clock hours away, got \(across.timeIntervalSince(beforeDST) / 3600)")
        precondition(Clock.next(minute: 0, after: afternoon) == date(2026, 9, 25, 0, 0, in: cal), "FAIL: midnight")
        precondition(Clock.short(59) == "1m" && Clock.short(61) == "2m" && Clock.short(3600) == "1h" && Clock.short(4320) == "1h 12m" && Clock.short(0) == "1m",
                     "FAIL: menu-bar time")
        precondition(Clock.suggestedMinute(after: date(2026, 9, 24, 17, 0, in: cal)) == 18 * 60
                     && Clock.suggestedMinute(after: date(2026, 9, 24, 17, 31, in: cal)) == 19 * 60
                     && Clock.suggestedMinute(after: date(2026, 9, 24, 23, 40, in: cal)) == 1 * 60, "FAIL: suggested time")
    }

    /// Schedule windows: day boundaries, overnight windows, all day, a DST day.
    private static func schedule() {
        let cal = auckland
        let wd = Schedule.weekdays, from = 9 * 60, to = 17 * 60
        let check = { (y: Int, mo: Int, d: Int, h: Int, mi: Int, days: Int, from: Int, to: Int, want: Bool, why: String) in
            precondition(Schedule.contains(date(y, mo, d, h, mi, in: cal), days: days, from: from, to: to, calendar: cal) == want, "FAIL: schedule: \(why)")
        }
        check(2026, 9, 25, 10, 0, wd, from, to, true, "Friday 10:00 is in the working week")       // 25 Sep 2026 is a Friday
        check(2026, 9, 25, 9, 0, wd, from, to, true, "the start minute is inside")
        check(2026, 9, 25, 17, 0, wd, from, to, false, "the end minute is outside")
        check(2026, 9, 25, 8, 59, wd, from, to, false, "just before the start")
        check(2026, 9, 26, 10, 0, wd, from, to, false, "Saturday is not a weekday")
        check(2026, 9, 27, 10, 0, Schedule.everyDay, from, to, true, "every day includes Sunday")
        check(2026, 9, 27, 10, 0, Schedule.weekend, from, to, true, "weekends include Sunday")
        check(2026, 9, 27, 10, 0, 0, from, to, false, "no days, never")
        let night = 22 * 60, dawn = 6 * 60
        check(2026, 9, 25, 23, 0, wd, night, dawn, true, "overnight: Friday 23:00 is in Friday's window")
        check(2026, 9, 26, 3, 0, wd, night, dawn, true, "overnight: Saturday 03:00 is still Friday's window")
        check(2026, 9, 26, 6, 0, wd, night, dawn, false, "overnight: it ends at 06:00")
        check(2026, 9, 26, 23, 0, wd, night, dawn, false, "overnight: Saturday night is not a weekday's window")
        check(2026, 9, 28, 3, 0, wd, night, dawn, false, "overnight: Monday 03:00 is Sunday's night")
        check(2026, 9, 28, 23, 0, wd, night, dawn, true, "overnight: Monday night")
        check(2026, 9, 27, 3, 0, Schedule.weekend, night, dawn, true, "overnight: Sunday 03:00 is Saturday's window")
        check(2026, 9, 27, 3, 30, wd, 0, 0, false, "all day, but Sunday")
        check(2026, 9, 25, 3, 30, wd, 0, 0, true, "0:00 – 0:00 is all day")
        check(2026, 9, 25, 23, 59, wd, 0, 0, true, "all day, last minute")
        check(2026, 9, 27, 3, 30, 1 << 7, night, dawn, true, "DST day (27 Sep, 02:00 → 03:00): 03:30 is still in Saturday night's window")
        check(2026, 9, 27, 5, 59, 1 << 7, night, dawn, true, "DST day: 05:59 too")
        check(2026, 9, 27, 6, 0, 1 << 7, night, dawn, false, "DST day: over at 06:00 wall-clock")
        precondition(Schedule.weekdays == 0b0111_1100 && Schedule.weekend == 0b1000_0010 && Schedule.everyDay == 0b1111_1110, "FAIL: day masks")
        precondition(Schedule.order.count == 7 && Set(Schedule.order) == Set(1...7), "FAIL: day order")
    }

    /// Reasons come out in panel order, only for rules that are on, and read as one sentence.
    private static func automations() {
        let cal = auckland
        var s = Settings()
        s.apps = [AppRef(id: "us.zoom.xos", name: "Zoom"), AppRef(id: "com.apple.iWork.Keynote", name: "Keynote")]
        let friday = date(2026, 9, 25, 10, 0, in: cal)
        let running: Set<String> = ["us.zoom.xos", "com.apple.finder"]
        precondition(Automation.reasons(s, running: running, onAC: true, externalDisplay: true, now: friday, calendar: cal).isEmpty, "FAIL: nothing on, no reasons")
        s.appsOn = true; s.powerOn = true; s.displayOn = true; s.scheduleOn = true
        let all = Automation.reasons(s, running: running, onAC: true, externalDisplay: true, now: friday, calendar: cal)
        precondition(all == [.app(s.apps[0]), .power, .display, .schedule], "FAIL: overlapping reasons in order: \(all)")
        precondition(Automation.sentence(all) == "While Zoom is running, on the power adapter, a display is connected and on the schedule", "FAIL: \(Automation.sentence(all))")
        precondition(Automation.sentence([.power]) == "While on the power adapter" && Automation.sentence([.app(s.apps[1]), .power]) == "While Keynote is running and on the power adapter"
                     && Automation.sentence([]) == "", "FAIL: sentences")
        let some = Automation.reasons(s, running: ["com.apple.iWork.Keynote"], onAC: false, externalDisplay: false, now: date(2026, 9, 26, 10, 0, in: cal), calendar: cal)
        precondition(some == [.app(s.apps[1])], "FAIL: only Keynote should hold on a Saturday on battery: \(some)")
        let both = Automation.reasons(s, running: ["us.zoom.xos", "com.apple.iWork.Keynote"], onAC: false, externalDisplay: false, now: date(2026, 9, 26, 10, 0, in: cal), calendar: cal)
        precondition(both == [.app(s.apps[0]), .app(s.apps[1])], "FAIL: two apps, both listed")
        s.appsOn = false
        precondition(!Automation.reasons(s, running: running, onAC: false, externalDisplay: false, now: friday, calendar: cal).contains(.power), "FAIL: on battery is not on power")
    }

    /// The URL scheme is an input boundary: only the known verbs and parameters, values clamped, everything else nil.
    private static func commands() {
        let parse = { (text: String) -> Command? in URL(string: text).flatMap(Command.parse) }
        precondition(parse("sleepless://on") == .on(minutes: nil, untilMinute: nil), "FAIL: on")
        precondition(parse("sleepless://on?minutes=30") == .on(minutes: 30, untilMinute: nil), "FAIL: on?minutes")
        precondition(parse("sleepless://on?minutes=999999") == .on(minutes: 1440, untilMinute: nil), "FAIL: minutes clamp to a day")
        precondition(parse("sleepless://on?until=17:30") == .on(minutes: nil, untilMinute: 1050), "FAIL: on?until")
        precondition(parse("sleepless://on?until=7:05") == .on(minutes: nil, untilMinute: 425), "FAIL: on?until one-digit hour")
        precondition(parse("sleepless://on?until=00:00") == .on(minutes: nil, untilMinute: 0), "FAIL: midnight")
        precondition(parse("sleepless://off") == .off && parse("sleepless://toggle") == .toggle, "FAIL: off / toggle")
        precondition(parse("SLEEPLESS://ON?MINUTES=15") == .on(minutes: 15, untilMinute: nil), "FAIL: case-insensitive")
        precondition(parse("sleepless://lid?on=1") == .lid(true) && parse("sleepless://lid?on=false") == .lid(false), "FAIL: lid")
        precondition(parse("sleepless://on/") == .on(minutes: nil, untilMinute: nil), "FAIL: a lone slash is fine")
        for hostile in ["sleepless://on?minutes=0", "sleepless://on?minutes=-5", "sleepless://on?minutes=abc", "sleepless://on?minutes=1e3", "sleepless://on?minutes=",
                        "sleepless://on?until=25:00", "sleepless://on?until=17:60", "sleepless://on?until=1730", "sleepless://on?until=17:3", "sleepless://on?until=",
                        "sleepless://on?minutes=30&until=17:30", "sleepless://on?minutes=30&minutes=60", "sleepless://on?seconds=30", "sleepless://on?minutes=30&x=1",
                        "sleepless://run?cmd=rm%20-rf%20/", "sleepless://on/../off", "sleepless://on/off", "sleepless://on#off", "sleepless://user@on", "sleepless://on:80",
                        "sleepless://lid", "sleepless://lid?on=maybe", "sleepless://lid?on=1&minutes=5", "sleepless://toggle?x=1", "sleepless://off?minutes=5",
                        "sleepless:on", "sleepless://", "https://on", "file:///etc/passwd", "sleepless://on?minutes=30%0Aopen%20x"] {
            precondition(parse(hostile) == nil, "FAIL: should be refused: \(hostile)")
        }
    }

    private static func hotKeys() {
        let key = HotKey(keyCode: 1, modifiers: HotKey.carbon([.control, .option, .command]), key: "S")
        precondition(key.label == "⌃⌥⌘S" && key.modifiers == 4096 + 2048 + 256, "FAIL: hot key label \(key.label) / \(key.modifiers)")
        precondition(HotKey(keyCode: 96, modifiers: 0, key: "F5").label == "F5" && HotKey(keyCode: 0, modifiers: HotKey.carbon([.shift, .command]), key: "A").label == "⇧⌘A", "FAIL: labels")
    }
}
