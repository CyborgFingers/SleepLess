import SwiftUI

/// Keep awake (lid open), with what the screen does when idle shown only while it is on.
struct ScreenCard: View {
    @ObservedObject var keeper: Keeper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let delays = [(0, "Right away"), (30, "30 seconds"), (60, "1 minute"), (120, "2 minutes"), (300, "5 minutes"), (600, "10 minutes")]

    private var animation: Animation? { reduceMotion ? nil : panelEase }
    private var percent: Int { Int((keeper.s.level * 100).rounded()) }

    /// What the screen does when idle: 0 stays on, 1 dims, 2 may sleep (the Mac stays awake either way).
    private var idle: Binding<Int> {
        Binding(get: { keeper.s.screenSleeps ? 2 : keeper.s.dims ? 1 : 0 },
                set: { choice in withAnimation(animation) { var n = keeper.s; n.dims = choice == 1; n.screenSleeps = choice == 2; keeper.s = n } })
    }

    private var subtitle: String {
        guard keeper.s.screenOn else { return "Lid open: the Mac never sleeps" }
        if keeper.s.screenSleeps { return "Screen may sleep, Mac stays awake" }
        return keeper.s.dims ? "Screen dims when idle, no sleep" : "Screen stays on, no idle sleep"
    }

    var body: some View {
        ModeCard(title: "Keep awake", subtitle: subtitle,
                 symbol: "sun.max.fill", tint: .orange,
                 help: "Holds the same power assertions as caffeinate -di: the Mac never idle-sleeps and, unless you let it, neither does the screen.",
                 isOn: Binding(get: { keeper.s.screenOn }, set: { on in withAnimation(animation) { keeper.s.screenOn = on } })) {
            if keeper.s.screenOn {
                Divider()
                HStack {
                    Text("When idle").font(.callout).frame(width: 70, alignment: .leading)
                    Picker("Screen when idle", selection: idle) {
                        Text("Stay on").tag(0)
                        Text("Dim").tag(1)
                        Text("Sleep").tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .help("What the screen does with no input. Stay on: never dims or sleeps. Dim: the built-in screen goes down to a brightness you pick after a delay, and any key press or mouse move brings it back. Sleep: the screen sleeps as usual (overnight downloads, renders) while the Mac stays awake.")
                }
                if keeper.s.dims && !keeper.s.screenSleeps {
                    HStack {
                        Text("Dim to").font(.callout).frame(width: 70, alignment: .leading)
                        Image(systemName: "sun.min").foregroundStyle(.secondary).imageScale(.small)
                        Slider(value: $keeper.s.level, in: 0...1) { Text("Dim to") }.labelsHidden()
                            .help("Brightness while idle. It never brightens a screen that is already darker than this.")
                            .accessibilityValue("\(percent) percent")
                        Text("\(percent)%").font(.callout).monospacedDigit().frame(width: 38, alignment: .trailing)
                            .contentTransition(.numericText())
                            .animation(animation, value: percent)
                    }
                    HStack {
                        Text("After").font(.callout).frame(width: 70, alignment: .leading)
                        Picker("Dim after", selection: $keeper.s.delay) {
                            ForEach(delays, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .labelsHidden().fixedSize()
                        .help("How long with no keyboard or mouse input before the screen dims.")
                        Spacer()
                    }
                }
            }
        }
    }
}

/// Keep awake with lid closed, its live status, and the safety rules tucked into a disclosure.
struct LidCard: View {
    @ObservedObject var keeper: Keeper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("safetyExpanded") private var safetyExpanded = false

    private var animation: Animation? { reduceMotion ? nil : panelEase }

    private var status: String {
        switch (keeper.s.lidOn, keeper.lidActive) {
        case (true, true): return "Close the lid: screen goes dark, Mac keeps running"
        case (true, false): return "Starting…"
        case (false, true): return "Sleep is already turned off by another app or setting"
        case (false, false): return keeper.helperReady ? "Lid closed: sleeps as usual" : keeper.helperUpdating ? "Updating the helper…" : "Needs the one-time setup"
        }
    }

    private var safetySummary: String {
        var parts: [String] = []
        if keeper.s.onlyWhileCharging { parts.append("Charging only") } else if keeper.s.batteryCutoff > 0 { parts.append("Stops at \(keeper.s.batteryCutoff)%") }
        if keeper.s.pauseWhenHot { parts.append("Pauses when hot") }
        if keeper.s.autoWhenCharging { parts.append("Auto on charger") }
        return parts.isEmpty ? "No limits" : parts.joined(separator: " · ")
    }

    var body: some View {
        ModeCard(title: "Keep awake with lid closed", subtitle: status,
                 symbol: "laptopcomputer", tint: .indigo,
                 help: "Keeps the Mac running with the lid shut by setting SleepDisabled through a small root helper (set up once, with your password or Touch ID). Closing the lid turns the screen and keyboard light down to off while everything keeps running; open it and you are right where you left off, without having to unlock. A watchdog restores normal sleep if SleepLess ever stops.",
                 disabled: !keeper.helperReady,
                 isOn: Binding(get: { keeper.s.lidOn }, set: { on in withAnimation(animation) { keeper.setLid(on) } })) {
            if !keeper.helperReady, !keeper.helperUpdating {
                HStack(spacing: 8) {
                    Text("Your password or Touch ID, once.").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button("Set up…") { keeper.setUpHelper() }.controlSize(.small)
                        .help("Installs the helper for lid-closed mode and the charging light. macOS asks for your password or Touch ID, this once.")
                }
            }
            Divider()
            DisclosureRow(title: "Safety", summary: safetySummary,
                          help: "Rules that turn lid-closed mode off (or keep it off) to protect your battery and your Mac.",
                          expanded: $safetyExpanded) {
                if let battery = keeper.battery { BatteryLabel(battery: battery) }
            }
            if safetyExpanded { SafetyRows(keeper: keeper) }
        }
    }
}

struct SafetyRows: View {
    @ObservedObject var keeper: Keeper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation? { reduceMotion ? nil : panelEase }
    private var cutoff: Int { keeper.s.batteryCutoff }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SwitchRow(title: "Only while charging",
                      help: "Lid-closed mode turns off, and refuses to turn on, unless the charger is connected.",
                      isOn: Binding(get: { keeper.s.onlyWhileCharging }, set: { on in withAnimation(animation) { keeper.s.onlyWhileCharging = on } }))
            SwitchRow(title: "Pause when running hot",
                      help: "Turns lid-closed mode off while macOS reports a serious or critical thermal state.",
                      isOn: $keeper.s.pauseWhenHot)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Low-battery cutoff").font(.callout)
                    Spacer()
                    Text(cutoff == 0 ? "Never" : "\(cutoff)%").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(animation, value: cutoff)
                }
                Slider(value: Binding(get: { Double(cutoff) }, set: { keeper.s.batteryCutoff = Int($0) }), in: 0...100, step: 5) {
                    Text("Low-battery cutoff")
                }
                .labelsHidden().controlSize(.small)
                .accessibilityValue(cutoff == 0 ? "Never" : "\(cutoff) percent")
            }
            .help(keeper.s.onlyWhileCharging ? "Not needed while “Only while charging” is on."
                                              : "On battery power, lid-closed mode turns off when the battery reaches this level. 0 = never.")
            .disabled(keeper.s.onlyWhileCharging)
            .opacity(keeper.s.onlyWhileCharging ? 0.45 : 1)
            SwitchRow(title: "Turn on when charging",
                      subtitle: keeper.helperReady ? "Off again when you unplug" : "Turn lid-closed mode on once first",
                      help: "Turns lid-closed mode on when you plug in and off when you unplug. A manual flip sticks until the next plug or unplug.",
                      isOn: Binding(get: { keeper.s.autoWhenCharging }, set: { keeper.setAutoWhenCharging($0) }))
            SwitchRow(title: "Charging light off when closed",
                      subtitle: "Back to normal when you open the lid",
                      help: "While the lid is shut in lid-closed mode, the MagSafe connector's light turns off; opening the lid gives it back to macOS in the right colour.",
                      isOn: $keeper.lightOffWithLid)
            Button("Reinstall helper…") { keeper.setUpHelper() }
                .buttonStyle(.link).font(.caption)
                .help("If lid-closed mode or the charging light ever stop working: reinstalls SleepLess's helper (one administrator prompt).")
        }
        .padding(.leading, 18)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }
}

/// The timer: never, a duration, or a time of day — with a progress bar while it runs (the header carries the
/// countdown) and, while one is set, the option of the time left beside the menu-bar icon.
struct TimerSection: View {
    @ObservedObject var keeper: Keeper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let durations = [(15, "In 15 minutes"), (30, "In 30 minutes"), (60, "In 1 hour"), (120, "In 2 hours"), (240, "In 4 hours")]
    private static let atTime = -1

    private var animation: Animation? { reduceMotion ? nil : panelEase }

    private var choice: Binding<Int> {
        Binding(get: { keeper.s.offAtMinute != nil ? Self.atTime : keeper.s.offAfter },
                set: { value in
                    withAnimation(animation) {
                        if value == Self.atTime { keeper.setOffAt(minute: Clock.suggestedMinute(after: Date())) } else { keeper.setOffAfter(value) }
                    }
                })
    }

    private var atMinute: Binding<Date> {
        Binding(get: { Clock.date(minute: keeper.s.offAtMinute ?? 0) }, set: { keeper.setOffAt(minute: Clock.minute(of: $0)) })
    }

    private var running: ClosedRange<Date>? {
        guard keeper.s.screenOn || keeper.s.lidOn, let offAt = keeper.s.offAt, offAt > .now else { return nil }
        let from = keeper.s.offFrom ?? offAt.addingTimeInterval(-Double(max(keeper.s.offAfter, 1) * 60))
        return min(from, offAt)...offAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Turn off", systemImage: "timer").font(.callout.weight(.medium))
                Picker("Turn off", selection: choice) {
                    Text("Never").tag(0)
                    ForEach(Self.durations, id: \.0) { Text($0.1).tag($0.0) }
                    Divider()
                    Text("At a time").tag(Self.atTime)
                }
                .labelsHidden().fixedSize()
                .help("Turns everything you switched on off after this long, or at this time, then normal sleep is back. Picking again restarts the countdown. Automations keep their own hours.")
                if keeper.s.offAtMinute != nil {
                    DatePicker("Turn off at", selection: atMinute, displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.stepperField).fixedSize()
                        .help("The time of day to turn everything off — today if it is still ahead, otherwise tomorrow.")
                }
                Spacer(minLength: 0)
                if running == nil, keeper.s.hasTimer {
                    Text("Starts when a mode is on").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let running {
                ProgressView(timerInterval: running, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear).controlSize(.small)
                    .accessibilityHidden(true)
            }
            if keeper.s.hasTimer {
                SwitchRow(title: "Time left in the menu bar",
                          help: "Shows how long is left (1h 12m) beside the menu-bar icon while the timer runs.",
                          isOn: $keeper.s.timeInMenuBar)
                    .padding(.leading, 30)
                    .transition(.opacity)
            }
        }
        .animation(animation, value: keeper.s.hasTimer)
    }
}
