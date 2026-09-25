import SwiftUI
import IOKit.pwr_mgt

// SleepLess — Lidless plus the lid-open case: keep the screen on (optionally dimmed) and/or keep the Mac
// awake with the lid closed, with Lidless's safety cut-offs, auto-off timer and launch at login.

@main struct SleepLessApp: App {
    @StateObject private var keeper = Keeper()

    init() {
        if CommandLine.arguments.contains("--selftest") { selfTest() }
    }

    var body: some Scene {
        MenuBarExtra {
            Panel(keeper: keeper)
        } label: {
            MenuLabel(icon: keeper.icon, isOn: keeper.s.screenOn || keeper.s.lidOn)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuLabel: View {
    @ObservedObject var icon: MenuIcon
    let isOn: Bool

    var body: some View {
        Image(nsImage: icon.image).accessibilityLabel(isOn ? "SleepLess: on" : "SleepLess: off")
    }
}

struct Panel: View {
    @ObservedObject var keeper: Keeper

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SleepLess").font(.headline)
                Spacer()
                if let battery = keeper.battery {
                    Label("\(battery.percent)%", systemImage: battery.onAC ? "battery.100percent.bolt" : "battery.75percent")
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Divider()
            ScreenSection(keeper: keeper)
            Divider()
            LidSection(keeper: keeper)
            Divider()
            TimerSection(keeper: keeper)
            if let note = keeper.note {
                HStack(alignment: .top) {
                    Label(note, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Spacer()
                    Button { keeper.note = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Toggle("Launch at login", isOn: Binding(get: { LoginItem.isOn }, set: { keeper.setLoginItem($0) }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// Title + subtitle on the left, a switch on the right.
struct SwitchRow: View {
    let title: String
    var subtitle: String?
    var bold = false
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(bold ? .body.weight(.semibold) : .callout)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .toggleStyle(.switch)
        .controlSize(bold ? .regular : .small)
    }
}

struct ScreenSection: View {
    @ObservedObject var keeper: Keeper
    private let delays = [(0, "Right away"), (30, "30 sec"), (60, "1 min"), (120, "2 min"), (300, "5 min"), (600, "10 min")]

    var body: some View {
        SwitchRow(title: "Keep screen awake",
                  subtitle: keeper.s.screenOn ? "Screen stays on, Mac won't sleep" : "Lid open, normal sleep",
                  bold: true, isOn: $keeper.s.screenOn)
        Picker("When idle", selection: $keeper.s.dims) {
            Text("Stay the same").tag(false)
            Text("Dim").tag(true)
        }
        .pickerStyle(.segmented)
        .font(.callout)
        if keeper.s.dims {
            HStack {
                Image(systemName: "sun.min")
                Slider(value: $keeper.s.level, in: 0...1)
                Text("\(Int((keeper.s.level * 100).rounded()))%").monospacedDigit().frame(width: 38, alignment: .trailing)
            }
            .font(.callout)
            Picker("Dim after", selection: $keeper.s.delay) {
                ForEach(delays, id: \.0) { Text($0.1).tag($0.0) }
            }
            .font(.callout)
        }
    }
}

struct LidSection: View {
    @ObservedObject var keeper: Keeper

    private var status: String {
        switch (keeper.s.lidOn, keeper.lidActive) {
        case (true, true): return "Active: close the lid and it keeps running"
        case (true, false): return "Starting…"
        case (false, true): return "Sleep is disabled by something else (Lidless? pmset?)"
        case (false, false): return keeper.helperReady ? "Normal lid-close sleep" : "Asks for your password once to install its helper"
        }
    }

    var body: some View {
        SwitchRow(title: "Keep awake with lid closed", subtitle: status, bold: true,
                  isOn: Binding(get: { keeper.s.lidOn }, set: { keeper.setLid($0) }))
        Text("Safety").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        SwitchRow(title: "Only while charging", isOn: $keeper.s.onlyWhileCharging)
        SwitchRow(title: "Pause when running hot", isOn: $keeper.s.pauseWhenHot)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Low-battery cutoff")
                Spacer()
                Text(keeper.s.batteryCutoff == 0 ? "Never" : "\(keeper.s.batteryCutoff)%").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(keeper.s.batteryCutoff) }, set: { keeper.s.batteryCutoff = Int($0) }), in: 0...100, step: 5)
                .controlSize(.small)
        }
        .font(.callout)
        .disabled(keeper.s.onlyWhileCharging)
        SwitchRow(title: "Automatically enable when charging",
                  subtitle: keeper.helperReady ? nil : "Turn lid-closed mode on once first",
                  isOn: Binding(get: { keeper.s.autoWhenCharging }, set: { keeper.setAutoWhenCharging($0) }))
    }
}

struct TimerSection: View {
    @ObservedObject var keeper: Keeper
    private let options = [(0, "No limit"), (15, "15 min"), (30, "30 min"), (60, "1 hour"), (120, "2 hours"), (240, "4 hours")]

    var body: some View {
        Picker("Turn off after", selection: Binding(get: { keeper.s.offAfter }, set: { keeper.setOffAfter($0) })) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .font(.callout)
        if let offAt = keeper.s.offAt, offAt > .now {
            Label {
                HStack(spacing: 4) {
                    Text("Turning off in")
                    Text(timerInterval: Date.now...offAt, countsDown: true).monospacedDigit()
                }
            } icon: {
                Image(systemName: "timer")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

/// `SleepLess.app/Contents/MacOS/SleepLess --selftest` checks the OS hooks still work after macOS updates
/// (briefly nudges brightness). The root helper's logic is covered by test-helper.sh.
private func selfTest() -> Never {
    guard let original = Brightness.get() else { fatalError("FAIL: can't read built-in brightness") }
    let probe: Float = original > 0.5 ? original - 0.1 : original + 0.1
    Brightness.set(probe)
    usleep(500_000)
    let readBack = Brightness.get() ?? -1
    Brightness.set(original)
    precondition(abs(readBack - probe) < 0.03, "FAIL: brightness set \(probe), read \(readBack)")

    let ids = Awake.hold()
    var byPID: Unmanaged<CFDictionary>?
    IOPMCopyAssertionsByProcess(&byPID)
    let types = Set(((byPID?.takeRetainedValue() as? [Int: [[String: Any]]])?[Int(getpid())] ?? []).compactMap { $0["AssertType"] as? String })
    ids.forEach { IOPMAssertionRelease($0) }
    precondition(types.isSuperset(of: ["PreventUserIdleDisplaySleep", "PreventUserIdleSystemSleep"]), "FAIL: assertions not registered: \(types)")

    precondition(Power.battery() != nil, "FAIL: can't read the battery")
    print("PASS: brightness round-trip, display/system sleep assertions, battery (SleepDisabled now \(Power.sleepDisabled))")
    exit(0)
}
