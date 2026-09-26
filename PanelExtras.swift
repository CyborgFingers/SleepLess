import AppKit
import SwiftUI

/// "Keep awake automatically when…": one switch per rule, all off by default, collapsed behind a summary line that
/// turns accent-coloured (and says why) while a rule is holding the Mac awake.
struct AutomationsSection: View {
    @ObservedObject var keeper: Keeper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("automationsExpanded") private var expanded = false

    private var animation: Animation? { reduceMotion ? nil : panelEase }
    private var live: Bool { !keeper.reasons.isEmpty }
    private var summary: String {
        guard live else { return Automation.summary(keeper.s) }
        let now = Automation.sentence(keeper.reasons, prefix: "")
        return now.prefix(1).uppercased() + now.dropFirst()
    }

    /// The row's subtitle while its rule is holding (or paused by a click).
    private func state(_ match: (Reason) -> Bool) -> (String?, Bool) {
        if keeper.reasons.contains(where: match) { return ("Keeping your Mac awake now", true) }
        if keeper.paused.contains(where: match) { return ("Paused until this ends — you switched off", false) }
        return (nil, false)
    }

    private func row(_ title: String, help: String, match: @escaping (Reason) -> Bool, isOn: Binding<Bool>) -> some View {
        let (subtitle, live) = state(match)
        return SwitchRow(title: title, subtitle: subtitle, live: live, help: help, isOn: isOn)
    }

    private func binding(_ path: WritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        Binding(get: { keeper.s[keyPath: path] }, set: { on in withAnimation(animation) { keeper.s[keyPath: path] = on } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureRow(title: "Automations", summary: summary, symbol: "bolt.badge.automatic", live: live,
                          help: "Keep the Mac awake by itself while an app is running, on the power adapter, with an external display, or on a schedule. A click on the icon pauses an automation until its reason ends.",
                          expanded: $expanded)
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Keep awake automatically…").font(.caption).foregroundStyle(.secondary)
                    row("While an app is running", help: "While any of the apps below is running — a call, a presentation, a build, an export.",
                        match: { if case .app = $0 { return true } else { return false } }, isOn: binding(\.appsOn))
                    if keeper.s.appsOn { AppRows(keeper: keeper) }
                    row("On the power adapter", help: "Whenever the Mac is plugged in. (On a desktop Mac, that is always.)",
                        match: { $0 == .power }, isOn: binding(\.powerOn))
                    row("With an external display", help: "While a monitor is connected — docked at a desk, or presenting.",
                        match: { $0 == .display }, isOn: binding(\.displayOn))
                    row("On a schedule", help: "On the days and between the times below. An end time earlier than the start runs overnight.",
                        match: { $0 == .schedule }, isOn: binding(\.scheduleOn))
                    if keeper.s.scheduleOn { ScheduleRows(keeper: keeper) }
                }
                .padding(.leading, 18)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// The chosen apps, each with its icon and a remove button, and an Add menu of the apps running now (or any app).
struct AppRows: View {
    @ObservedObject var keeper: Keeper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation? { reduceMotion ? nil : panelEase }
    private var running: Set<String> { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }

    private func add(_ app: AppRef) {
        guard !keeper.s.apps.contains(where: { $0.id == app.id }) else { return }
        withAnimation(animation) { keeper.s.apps.append(app) }
    }

    private func chooseOther() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an app: SleepLess keeps the Mac awake while it is running."
        panel.prompt = "Add"
        panel.begin { response in
            guard response == .OK, let url = panel.url, let app = AppRef(url: url) else { return }
            MainActor.assumeIsolated { add(app) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(keeper.s.apps, id: \.id) { app in
                HStack(spacing: 8) {
                    Image(nsImage: app.icon).resizable().frame(width: 18, height: 18).accessibilityHidden(true)
                    Text(app.name).font(.callout).lineLimit(1)
                    if running.contains(app.id) { Text("running").font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(animation) { keeper.s.apps.removeAll { $0.id == app.id } }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(app.name)")
                    .accessibilityLabel("Remove \(app.name)")
                }
                .accessibilityElement(children: .combine)
            }
            Menu {
                let chosen = Set(keeper.s.apps.map(\.id))
                ForEach(AppWatch.visible.filter { !chosen.contains($0.id) && $0.id != Bundle.main.bundleIdentifier }, id: \.id) { app in
                    Button { add(app) } label: { Label { Text(app.name) } icon: { Image(nsImage: app.icon) } }
                }
                Divider()
                Button("Other…") { chooseOther() }
            } label: {
                Label("Add app", systemImage: "plus")
            }
            .controlSize(.small).fixedSize()
            .help("The apps running now, or Other… to pick any app.")
        }
        .padding(.leading, 4)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }
}

/// Days of the week as small toggle buttons, and the window's start and end times.
struct ScheduleRows: View {
    @ObservedObject var keeper: Keeper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func day(_ weekday: Int) -> Binding<Bool> {
        Binding(get: { keeper.s.days & 1 << weekday != 0 },
                set: { on in keeper.s.days = on ? keeper.s.days | 1 << weekday : keeper.s.days & ~(1 << weekday) })
    }

    private func time(_ path: WritableKeyPath<Settings, Int>) -> Binding<Date> {
        Binding(get: { Clock.date(minute: keeper.s[keyPath: path]) }, set: { keeper.s[keyPath: path] = Clock.minute(of: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Schedule.order, id: \.self) { weekday in
                    Toggle(Calendar.current.veryShortWeekdaySymbols[weekday - 1], isOn: day(weekday))
                        .toggleStyle(.button).controlSize(.small)
                        .help(Calendar.current.weekdaySymbols[weekday - 1])
                        .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                }
            }
            HStack(spacing: 6) {
                Text("From").font(.callout)
                DatePicker("From", selection: time(\.from), displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.stepperField).fixedSize()
                Text("to").font(.callout)
                DatePicker("To", selection: time(\.to), displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.stepperField).fixedSize()
                Spacer(minLength: 0)
            }
            .help("An end time at or before the start runs overnight, and 0:00 to 0:00 is all day.")
            Text(Schedule.summary(days: keeper.s.days, from: keeper.s.from, to: keeper.s.to)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }
}

/// The keyboard shortcut, notifications, and the URL scheme for Shortcuts and scripts.
struct MoreSection: View {
    @ObservedObject var keeper: Keeper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("moreExpanded") private var expanded = false

    private var summary: String {
        var parts: [String] = []
        if let key = keeper.s.hotKey { parts.append("Shortcut \(key.label)") }
        if keeper.s.notify { parts.append("Notifications on") }
        return parts.isEmpty ? "Shortcut, notifications, scripting" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureRow(title: "More", summary: summary, symbol: "ellipsis.circle",
                          help: "A global keyboard shortcut, notifications, and the sleepless:// commands for Shortcuts and scripts.",
                          expanded: $expanded)
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Keyboard shortcut").font(.callout)
                            Text("Works in any app: the same as a click on the icon").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        ShortcutRecorder(hotKey: $keeper.s.hotKey)
                    }
                    SwitchRow(title: "Notify me",
                              subtitle: "When a timer ends or a safety rule turns lid-closed mode off",
                              help: "macOS asks for permission when you turn this on. SleepLess sends nothing else.",
                              isOn: Binding(get: { keeper.s.notify }, set: { keeper.setNotify($0) }))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scripting").font(.callout)
                        Text("Open sleepless://on, off, toggle, on?minutes=30, on?until=17:30 or lid?on=1 from a shortcut, a script or a shell.")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .help("From a shortcut (Open URLs), a script or a shell: open \"sleepless://on?minutes=30\". on turns SleepLess on — with a duration or until a time (24-hour clock) — off turns it off, toggle flips it, lid?on=1 or 0 switches lid-closed mode. Nothing else is accepted.")
                }
                .padding(.leading, 18)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Click, press the keys, done. Esc cancels; the × removes the shortcut.
struct ShortcutRecorder: View {
    @Binding var hotKey: HotKey?
    @State private var recording = false
    @State private var monitor: Any?

    private func start() {
        recording = true
        HotKeys.recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 { stop(); return }   // Esc: keep what was there
                if let key = HotKey(event: event) { hotKey = key; stop() }
            }
            return nil   // nothing typed while recording reaches the panel
        }
    }

    private func stop() {
        recording = false
        HotKeys.recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(recording ? "Press keys…" : hotKey?.label ?? "Record shortcut") { recording ? stop() : start() }
                .controlSize(.small)
                .help(recording ? "Press the keys you want, with ⌘, ⌃ or ⌥ (or a function key). Esc cancels."
                                : hotKey == nil ? "Set a shortcut that turns SleepLess on or off from any app." : "Change the shortcut.")
                .accessibilityLabel(recording ? "Recording shortcut, press keys" : hotKey.map { "Shortcut \($0.label)" } ?? "Record shortcut")
            if hotKey != nil, !recording {
                Button { hotKey = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help("Remove the shortcut")
                    .accessibilityLabel("Remove the shortcut")
            }
        }
        .onDisappear { if recording { stop() } }
    }
}
