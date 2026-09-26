import AppKit

// "Keep awake automatically when…": standing rules the reconcile loop evaluates from things it already knows
// (the running apps, power, displays, the clock). The rules are pure and selftested; AppWatch is the one
// event source — no polling, NSWorkspace tells it when an app starts or quits.

/// An app chosen for the "while an app is running" rule: bundle id to match on, name to show.
struct AppRef: Codable, Equatable, Hashable {
    var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init?(url: URL) {
        guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        self.init(id: id, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
    }

    init?(running app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
        self.init(id: id, name: name)
    }

    /// Its icon from disk; a generic one if it isn't installed any more.
    var icon: NSImage {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

/// Why an automation is keeping the Mac awake, in the order the panel lists the rules.
enum Reason: Hashable {
    case app(AppRef), power, display, schedule

    var phrase: String {
        switch self {
        case .app(let app): return "\(app.name) is running"
        case .power: return "on the power adapter"
        case .display: return "a display is connected"
        case .schedule: return "on the schedule"
        }
    }
}

enum Automation {
    /// The rules that hold right now.
    nonisolated static func reasons(_ s: Settings, running: Set<String>, onAC: Bool, externalDisplay: Bool, now: Date, calendar: Calendar = .current) -> [Reason] {
        var out: [Reason] = []
        if s.appsOn { out += s.apps.filter { running.contains($0.id) }.map(Reason.app) }
        if s.powerOn, onAC { out.append(.power) }
        if s.displayOn, externalDisplay { out.append(.display) }
        if s.scheduleOn, Schedule.contains(now, days: s.days, from: s.from, to: s.to, calendar: calendar) { out.append(.schedule) }
        return out
    }

    /// "While FaceTime is running", "While FaceTime is running and on the power adapter",
    /// "While FaceTime is running, on the power adapter and on the schedule".
    nonisolated static func sentence(_ reasons: [Reason], prefix: String = "While ") -> String {
        let phrases = reasons.map(\.phrase)
        switch phrases.count {
        case 0: return ""
        case 1: return prefix + phrases[0]
        default: return prefix + phrases.dropLast().joined(separator: ", ") + " and " + phrases.last!
        }
    }

    /// What the collapsed section says: the rules that are on, e.g. "FaceTime, Keynote · On power · Weekdays 9:00 AM – 5:00 PM".
    static func summary(_ s: Settings) -> String {
        var parts: [String] = []
        if s.appsOn { parts.append(s.apps.isEmpty ? "No apps chosen" : s.apps.map(\.name).joined(separator: ", ")) }
        if s.powerOn { parts.append("On power") }
        if s.displayOn { parts.append("External display") }
        if s.scheduleOn { parts.append(Schedule.summary(days: s.days, from: s.from, to: s.to)) }
        return parts.isEmpty ? "Off" : parts.joined(separator: " · ")
    }
}

/// Days are a bitmask by Calendar weekday (1 = Sunday … 7 = Saturday); the window is minutes past midnight, and
/// `to <= from` runs overnight (22:00 – 06:00 belongs to the day it starts on; 0:00 – 0:00 is all day).
enum Schedule {
    static let weekdays = (2...6).reduce(0) { $0 | 1 << $1 }
    static let weekend = 1 << 1 | 1 << 7
    static let everyDay = weekdays | weekend

    nonisolated static func contains(_ now: Date, days: Int, from: Int, to: Int, calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        return contains(minute: c.hour! * 60 + c.minute!, weekday: c.weekday!, days: days, from: from, to: to)
    }

    /// Wall-clock only, so a 23- or 25-hour DST day changes nothing.
    nonisolated static func contains(minute: Int, weekday: Int, days: Int, from: Int, to: Int) -> Bool {
        let today = days & 1 << weekday != 0
        let yesterday = days & 1 << (weekday == 1 ? 7 : weekday - 1) != 0
        if from < to { return today && minute >= from && minute < to }
        return (today && minute >= from) || (yesterday && minute < to)
    }

    /// "Weekdays 9:00 AM – 5:00 PM", "Every day", "Mon, Wed, Fri 10:00 PM – 6:00 AM", "No days".
    static func summary(days: Int, from: Int, to: Int) -> String {
        let when: String
        switch days & everyDay {
        case 0: return "No days"
        case everyDay: when = "Every day"
        case weekdays: when = "Weekdays"
        case weekend: when = "Weekends"
        default:
            let calendar = Calendar.current
            when = order.filter { days & 1 << $0 != 0 }.map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        }
        let allDay = from == to
        return allDay ? when : "\(when) \(Clock.label(minute: from)) – \(Clock.label(minute: to))"
    }

    /// Weekday numbers starting on the locale's first day of the week.
    static var order: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}

/// The running apps, kept current by NSWorkspace's launch and quit notifications (no permission, no polling).
@MainActor final class AppWatch {
    private(set) var running = AppWatch.snapshot()
    var changed: () -> Void = {}

    init() {
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    self.running = Self.snapshot()
                    self.changed()
                }
            }
        }
    }

    private static func snapshot() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Apps with a Dock presence, for the "Add app" menu.
    static var visible: [AppRef] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(AppRef.init(running:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
