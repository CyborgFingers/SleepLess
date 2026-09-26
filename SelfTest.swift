import Foundation

/// The pure parts behind the timer, automations, the URL scheme and settings migration, run by --selftest.
/// Every check is one short statement: long `&&` chains take the type-checker minutes.
enum SelfTest {
    static func features() {
        settings()
        clock()
        schedule()
        automations()
        commands()
        hotKeys()
    }

    private static func check(_ ok: Bool, _ what: String) {
        precondition(ok, "FAIL: \(what)")
    }

    private static func decode(_ json: String) -> Settings {
        try! JSONDecoder().decode(Settings.self, from: json.data(using: .utf8)!)
    }

    /// A settings blob exactly as 1.2.1 wrote it must keep every value and take defaults for the new fields;
    /// an empty or partly broken blob must never throw the rest away.
    private static func settings() {
        let s = decode(#"{"screenOn":true,"dims":true,"level":0.35,"delay":120,"lidOn":false,"onlyWhileCharging":true,"pauseWhenHot":false,"batteryCutoff":30,"autoWhenCharging":true,"offAfter":60,"offAt":780000000.5}"#)
        check(s.screenOn, "1.2.1 screenOn kept")
        check(s.dims, "1.2.1 dims kept")
        check(s.level == 0.35, "1.2.1 level kept")
        check(s.delay == 120, "1.2.1 delay kept")
        check(!s.lidOn, "1.2.1 lidOn kept")
        check(s.onlyWhileCharging, "1.2.1 onlyWhileCharging kept")
        check(!s.pauseWhenHot, "1.2.1 pauseWhenHot kept")
        check(s.batteryCutoff == 30, "1.2.1 batteryCutoff kept")
        check(s.autoWhenCharging, "1.2.1 autoWhenCharging kept")
        check(s.offAfter == 60, "1.2.1 offAfter kept")
        check(s.offAt == Date(timeIntervalSinceReferenceDate: 780000000.5), "1.2.1 offAt kept")
        let fresh = Settings()
        check(!s.screenSleeps, "new: screenSleeps default")
        check(s.offAtMinute == nil, "new: offAtMinute default")
        check(s.offFrom == nil, "new: offFrom default")
        check(!s.appsOn, "new: appsOn default")
        check(s.apps.isEmpty, "new: apps default")
        check(!s.powerOn, "new: powerOn default")
        check(!s.displayOn, "new: displayOn default")
        check(!s.scheduleOn, "new: scheduleOn default")
        check(s.days == fresh.days, "new: days default")
        check(s.from == fresh.from, "new: from default")
        check(s.to == fresh.to, "new: to default")
        check(!s.timeInMenuBar, "new: timeInMenuBar default")
        check(!s.notify, "new: notify default")
        check(s.hotKey == nil, "new: hotKey default")
        check(decode("{}") == fresh, "an empty blob is the defaults")
        let broken = decode(#"{"level":"high","offAfter":30,"apps":5}"#)
        check(broken.level == fresh.level, "a wrong-typed key counts as missing")
        check(broken.offAfter == 30, "the good keys beside it are kept")
        check(broken.apps.isEmpty, "a wrong-typed array counts as missing")
        var full = fresh
        full.apps = [AppRef(id: "com.apple.FaceTime", name: "FaceTime")]
        full.hotKey = HotKey(keyCode: 1, modifiers: 4352, key: "S")
        full.offAtMinute = 17 * 60 + 30
        full.offFrom = Date(timeIntervalSinceReferenceDate: 1)
        let again = try! JSONDecoder().decode(Settings.self, from: try! JSONEncoder().encode(full))
        check(again == full, "settings round-trip")
        check(decode(#"{"screenOn":true,"somethingFrom2027":[1,2]}"#).screenOn, "a key from a newer version is ignored")
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
        check(Clock.next(minute: 17 * 60 + 30, after: afternoon, calendar: cal) == date(2026, 9, 24, 17, 30, in: cal), "17:30 is later today")
        check(Clock.next(minute: 9 * 60, after: afternoon, calendar: cal) == date(2026, 9, 25, 9, 0, in: cal), "09:00 is tomorrow")
        check(Clock.next(minute: 17 * 60, after: afternoon, calendar: cal) == date(2026, 9, 25, 17, 0, in: cal), "the current minute means tomorrow")
        check(Clock.next(minute: 0, after: afternoon, calendar: cal) == date(2026, 9, 25, 0, 0, in: cal), "midnight")
        let beforeDST = date(2026, 9, 26, 23, 0, in: cal)
        let across = Clock.next(minute: 5 * 60, after: beforeDST, calendar: cal)
        check(cal.component(.hour, from: across) == 5, "05:00 across the DST change lands at 05:00")
        check(cal.component(.day, from: across) == 27, "05:00 across the DST change lands on the 27th")
        check(across.timeIntervalSince(beforeDST) == 5 * 3600, "05:00 across the DST change is 5 real hours away")
        check(Clock.short(59) == "1m", "menu-bar time: under a minute")
        check(Clock.short(61) == "2m", "menu-bar time: rounds up")
        check(Clock.short(3600) == "1h", "menu-bar time: a whole hour")
        check(Clock.short(4320) == "1h 12m", "menu-bar time: hours and minutes")
        check(Clock.short(0) == "1m", "menu-bar time: never zero")
        check(Clock.suggestedMinute(after: date(2026, 9, 24, 17, 0, in: cal), calendar: cal) == 18 * 60, "suggested time at 17:00")
        check(Clock.suggestedMinute(after: date(2026, 9, 24, 17, 31, in: cal), calendar: cal) == 19 * 60, "suggested time at 17:31")
        check(Clock.suggestedMinute(after: date(2026, 9, 24, 23, 40, in: cal), calendar: cal) == 1 * 60, "suggested time wraps past midnight")
    }

    /// Schedule windows: day boundaries, overnight windows, all day, a DST day.
    private static func schedule() {
        let cal = auckland
        let wd = Schedule.weekdays, from = 9 * 60, to = 17 * 60
        func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, days: Int, from: Int, to: Int) -> Bool {
            Schedule.contains(date(y, mo, d, h, mi, in: cal), days: days, from: from, to: to, calendar: cal)
        }
        check(at(2026, 9, 25, 10, 0, days: wd, from: from, to: to), "Friday 10:00 is in the working week")   // 25 Sep 2026 is a Friday
        check(at(2026, 9, 25, 9, 0, days: wd, from: from, to: to), "the start minute is inside")
        check(!at(2026, 9, 25, 17, 0, days: wd, from: from, to: to), "the end minute is outside")
        check(!at(2026, 9, 25, 8, 59, days: wd, from: from, to: to), "just before the start")
        check(!at(2026, 9, 26, 10, 0, days: wd, from: from, to: to), "Saturday is not a weekday")
        check(at(2026, 9, 27, 10, 0, days: Schedule.everyDay, from: from, to: to), "every day includes Sunday")
        check(at(2026, 9, 27, 10, 0, days: Schedule.weekend, from: from, to: to), "weekends include Sunday")
        check(!at(2026, 9, 27, 10, 0, days: 0, from: from, to: to), "no days, never")
        let night = 22 * 60, dawn = 6 * 60
        check(at(2026, 9, 25, 23, 0, days: wd, from: night, to: dawn), "overnight: Friday 23:00 is in Friday's window")
        check(at(2026, 9, 26, 3, 0, days: wd, from: night, to: dawn), "overnight: Saturday 03:00 is still Friday's window")
        check(!at(2026, 9, 26, 6, 0, days: wd, from: night, to: dawn), "overnight: it ends at 06:00")
        check(!at(2026, 9, 26, 23, 0, days: wd, from: night, to: dawn), "overnight: Saturday night is not a weekday's window")
        check(!at(2026, 9, 28, 3, 0, days: wd, from: night, to: dawn), "overnight: Monday 03:00 is Sunday's night")
        check(at(2026, 9, 28, 23, 0, days: wd, from: night, to: dawn), "overnight: Monday night")
        check(at(2026, 9, 27, 3, 0, days: Schedule.weekend, from: night, to: dawn), "overnight: Sunday 03:00 is Saturday's window")
        check(!at(2026, 9, 27, 3, 30, days: wd, from: 0, to: 0), "all day, but Sunday")
        check(at(2026, 9, 25, 3, 30, days: wd, from: 0, to: 0), "0:00 – 0:00 is all day")
        check(at(2026, 9, 25, 23, 59, days: wd, from: 0, to: 0), "all day, last minute")
        let saturday = 1 << 7
        check(at(2026, 9, 27, 3, 30, days: saturday, from: night, to: dawn), "DST day (27 Sep, 02:00 → 03:00): 03:30 is still in Saturday night's window")
        check(at(2026, 9, 27, 5, 59, days: saturday, from: night, to: dawn), "DST day: 05:59 too")
        check(!at(2026, 9, 27, 6, 0, days: saturday, from: night, to: dawn), "DST day: over at 06:00 wall-clock")
        check(Schedule.weekdays == 0b0111_1100, "weekday mask")
        check(Schedule.weekend == 0b1000_0010, "weekend mask")
        check(Schedule.everyDay == 0b1111_1110, "every-day mask")
        check(Schedule.order.count == 7, "day order has 7 days")
        check(Set(Schedule.order) == Set(1...7), "day order covers every weekday")
    }

    /// Reasons come out in panel order, only for rules that are on, and read as one sentence.
    private static func automations() {
        let cal = auckland
        var s = Settings()
        let facetime = AppRef(id: "com.apple.FaceTime", name: "FaceTime"), keynote = AppRef(id: "com.apple.iWork.Keynote", name: "Keynote")
        s.apps = [facetime, keynote]
        let friday = date(2026, 9, 25, 10, 0, in: cal)
        let saturday = date(2026, 9, 26, 10, 0, in: cal)
        let running: Set<String> = ["com.apple.FaceTime", "com.apple.finder"]
        let none = Automation.reasons(s, running: running, onAC: true, externalDisplay: true, now: friday, calendar: cal)
        check(none.isEmpty, "nothing on, no reasons")
        s.appsOn = true
        s.powerOn = true
        s.displayOn = true
        s.scheduleOn = true
        let all = Automation.reasons(s, running: running, onAC: true, externalDisplay: true, now: friday, calendar: cal)
        check(all == [.app(facetime), .power, .display, .schedule], "overlapping reasons in order: \(all)")
        check(Automation.sentence(all) == "While FaceTime is running, on the power adapter, a display is connected and on the schedule", "four reasons: \(Automation.sentence(all))")
        check(Automation.sentence([.power]) == "While on the power adapter", "one reason")
        check(Automation.sentence([.app(keynote), .power]) == "While Keynote is running and on the power adapter", "two reasons")
        check(Automation.sentence([]) == "", "no reasons")
        let some = Automation.reasons(s, running: ["com.apple.iWork.Keynote"], onAC: false, externalDisplay: false, now: saturday, calendar: cal)
        check(some == [.app(keynote)], "only Keynote holds on a Saturday on battery: \(some)")
        let both = Automation.reasons(s, running: ["com.apple.FaceTime", "com.apple.iWork.Keynote"], onAC: false, externalDisplay: false, now: saturday, calendar: cal)
        check(both == [.app(facetime), .app(keynote)], "two apps, both listed")
        s.appsOn = false
        let battery = Automation.reasons(s, running: running, onAC: false, externalDisplay: false, now: friday, calendar: cal)
        check(!battery.contains(.power), "on battery is not on power")
    }

    /// The URL scheme is an input boundary: only the known verbs and parameters, values clamped, everything else nil.
    private static func commands() {
        func parse(_ text: String) -> Command? { URL(string: text).flatMap(Command.parse) }
        check(parse("sleepless://on") == .on(minutes: nil, untilMinute: nil), "on")
        check(parse("sleepless://on?minutes=30") == .on(minutes: 30, untilMinute: nil), "on?minutes")
        check(parse("sleepless://on?minutes=999999") == .on(minutes: 1440, untilMinute: nil), "minutes clamp to a day")
        check(parse("sleepless://on?until=17:30") == .on(minutes: nil, untilMinute: 1050), "on?until")
        check(parse("sleepless://on?until=7:05") == .on(minutes: nil, untilMinute: 425), "on?until one-digit hour")
        check(parse("sleepless://on?until=00:00") == .on(minutes: nil, untilMinute: 0), "midnight")
        check(parse("sleepless://off") == .off, "off")
        check(parse("sleepless://toggle") == .toggle, "toggle")
        check(parse("SLEEPLESS://ON?MINUTES=15") == .on(minutes: 15, untilMinute: nil), "case-insensitive")
        check(parse("sleepless://lid?on=1") == .lid(true), "lid on")
        check(parse("sleepless://lid?on=false") == .lid(false), "lid off")
        check(parse("sleepless://on/") == .on(minutes: nil, untilMinute: nil), "a lone slash is fine")
        let hostile = ["sleepless://on?minutes=0", "sleepless://on?minutes=-5", "sleepless://on?minutes=abc", "sleepless://on?minutes=1e3", "sleepless://on?minutes=",
                       "sleepless://on?until=25:00", "sleepless://on?until=17:60", "sleepless://on?until=1730", "sleepless://on?until=17:3", "sleepless://on?until=",
                       "sleepless://on?minutes=30&until=17:30", "sleepless://on?minutes=30&minutes=60", "sleepless://on?seconds=30", "sleepless://on?minutes=30&x=1",
                       "sleepless://run?cmd=rm%20-rf%20/", "sleepless://on/../off", "sleepless://on/off", "sleepless://on#off", "sleepless://user@on", "sleepless://on:80",
                       "sleepless://lid", "sleepless://lid?on=maybe", "sleepless://lid?on=1&minutes=5", "sleepless://toggle?x=1", "sleepless://off?minutes=5",
                       "sleepless:on", "sleepless://", "https://on", "file:///etc/passwd", "sleepless://on?minutes=30%0Aopen%20x"]
        for text in hostile { check(parse(text) == nil, "should be refused: \(text)") }
    }

    private static func hotKeys() {
        let key = HotKey(keyCode: 1, modifiers: HotKey.carbon([.control, .option, .command]), key: "S")
        check(key.label == "⌃⌥⌘S", "hot key label \(key.label)")
        check(key.modifiers == 4096 + 2048 + 256, "carbon modifiers \(key.modifiers)")
        check(HotKey(keyCode: 96, modifiers: 0, key: "F5").label == "F5", "function key label")
        check(HotKey(keyCode: 0, modifiers: HotKey.carbon([.shift, .command]), key: "A").label == "⇧⌘A", "shift-command label")
    }
}
