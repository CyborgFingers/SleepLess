import SwiftUI

/// Keep screen awake (lid open), with the dim-when-idle options shown only while it is on.
struct ScreenCard: View {
    @ObservedObject var keeper: Keeper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let delays = [(0, "Right away"), (30, "30 seconds"), (60, "1 minute"), (120, "2 minutes"), (300, "5 minutes"), (600, "10 minutes")]

    private var animation: Animation? { reduceMotion ? nil : panelEase }
    private var percent: Int { Int((keeper.s.level * 100).rounded()) }

    var body: some View {
        ModeCard(title: "Keep screen awake",
                 subtitle: keeper.s.screenOn ? "Screen stays on, no idle sleep" : "Lid open: the screen never sleeps",
                 symbol: "sun.max.fill", tint: .orange,
                 help: "Holds the same power assertions as caffeinate -di: the screen never idle-dims or sleeps and the Mac never idle-sleeps.",
                 isOn: Binding(get: { keeper.s.screenOn }, set: { on in withAnimation(animation) { keeper.s.screenOn = on } })) {
            if keeper.s.screenOn {
                Divider()
                HStack {
                    Text("When idle").font(.callout).frame(width: 70, alignment: .leading)
                    Picker("When idle", selection: Binding(get: { keeper.s.dims }, set: { dims in withAnimation(animation) { keeper.s.dims = dims } })) {
                        Text("Stay the same").tag(false)
                        Text("Dim").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .help("Dim lowers the built-in screen's brightness after a delay with no input. Any key press or mouse move brings it back.")
                }
                if keeper.s.dims {
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
        case (false, true): return "Sleep is already disabled by something else (pmset? Lidless?)"
        case (false, false): return keeper.helperReady ? "Lid closed: sleeps as usual" : "Set up once with your password"
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
                 help: "Keeps the Mac running with the lid shut by setting SleepDisabled through a small root helper (one password prompt the first time). Closing the lid turns the screen and keyboard light down to off while everything keeps running; open it and you are right where you left off, without having to unlock. A watchdog restores normal sleep if SleepLess ever stops.",
                 isOn: Binding(get: { keeper.s.lidOn }, set: { on in withAnimation(animation) { keeper.setLid(on) } })) {
            Divider()
            Button {
                withAnimation(animation) { safetyExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(safetyExpanded ? 90 : 0))
                        .frame(width: 12)
                    Text("Safety").font(.callout.weight(.medium))
                    Text(safetySummary).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        .contentTransition(.opacity)
                        .animation(animation, value: safetySummary)
                    Spacer(minLength: 8)
                    if let battery = keeper.battery { BatteryLabel(battery: battery) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rules that turn lid-closed mode off (or keep it off) to protect your battery and your Mac.")
            .accessibilityLabel("Safety rules: \(safetySummary)")
            .accessibilityValue(safetyExpanded ? "expanded" : "collapsed")
            .accessibilityAddTraits(.isButton)
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
        }
        .padding(.leading, 18)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }
}

/// Auto-off timer: quick picks plus a live countdown and progress bar while it runs.
struct TimerSection: View {
    @ObservedObject var keeper: Keeper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let options = [(0, "Never"), (15, "15 min"), (30, "30 min"), (60, "1 hr"), (120, "2 hr"), (240, "4 hr")]

    private var animation: Animation? { reduceMotion ? nil : panelEase }
    private var running: ClosedRange<Date>? {
        guard let offAt = keeper.s.offAt, offAt > .now else { return nil }
        return offAt.addingTimeInterval(-Double(keeper.s.offAfter * 60))...offAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Turn off after", systemImage: "timer").font(.callout.weight(.medium))
                Spacer()
                if let running {
                    (Text(timerInterval: running, countsDown: true) + Text(" left"))
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityLabel("Turning everything off in")
                } else if keeper.s.offAfter > 0 {
                    Text("Starts when a mode is on").font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker("Turn off after", selection: Binding(get: { keeper.s.offAfter }, set: { m in withAnimation(animation) { keeper.setOffAfter(m) } })) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .help("Turns everything off after this long, then normal sleep is back. Picking a new value restarts the countdown.")
            if let running {
                ProgressView(timerInterval: running, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear).controlSize(.small)
                    .accessibilityHidden(true)
            }
        }
    }
}
