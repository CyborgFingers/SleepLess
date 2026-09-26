import SwiftUI

// The menu-bar panel: a live status header, one card per mode, the auto-off timer and a footer.
// Every control here maps 1:1 onto `Settings` / a Keeper action; the layout only adds progressive disclosure.

/// One curve for every panel transition; callers pass nil (no animation) under Reduce Motion.
let panelEase = Animation.easeInOut(duration: 0.25)

/// The sunrise palette from the app icon, used only for the glyph and its glow.
enum Sunrise {
    static let cream = Color(red: 1, green: 0.85, blue: 0.66)
    static let sun = Color(red: 1, green: 0.70, blue: 0.35)
    static let coral = Color(red: 0.89, green: 0.38, blue: 0.31)
    static let gradient = LinearGradient(colors: [cream, sun, coral], startPoint: .top, endPoint: .bottom)
}

struct Panel: View {
    @ObservedObject var keeper: Keeper
    var iconHidden = false   // shown in a floating panel because a full menu bar has hidden the icon
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("tapHintSeen") private var tapHintSeen = false
    @State private var iconNoteSeen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusHeader(keeper: keeper)
            if iconHidden, !iconNoteSeen {
                Notice(text: "Your menu bar is full, so macOS has hidden SleepLess's icon. Hold ⌘ and drag other icons out of the menu bar to make room.", kind: .tip) {
                    withAnimation(reduceMotion ? nil : panelEase) { iconNoteSeen = true }
                }
                .transition(.opacity)
            }
            if let note = keeper.note {
                Notice(text: note, kind: note.hasPrefix("Timer finished") ? .info : .warning) { keeper.note = nil }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            if !tapHintSeen {
                Notice(text: "Click the menu-bar icon to turn SleepLess on or off. Hold it, or right-click, for these settings.", kind: .tip) {
                    withAnimation(reduceMotion ? nil : panelEase) { tapHintSeen = true }
                }
                .transition(.opacity)
            }
            if !keeper.helperReady, !keeper.setupLater {
                SetupCard(appName: "SleepLess", what: "Lid-closed mode and the charging light", updating: keeper.helperStale, busy: keeper.helperUpdating,
                          setUp: { keeper.setUpHelper() }, later: { withAnimation(reduceMotion ? nil : panelEase) { keeper.setupLater = true } })
                    .transition(.opacity)
            }
            UpdateCard(updater: .shared)
            ScreenCard(keeper: keeper)
            LidCard(keeper: keeper)
            TimerSection(keeper: keeper)
            AutomationsSection(keeper: keeper)
            MoreSection(keeper: keeper)
            Divider()
            HStack {
                Toggle("Launch at login", isOn: Binding(get: { LoginItem.isOn }, set: { keeper.setLoginItem($0) }))
                    .toggleStyle(.checkbox)
                    .help("Start SleepLess automatically when you log in.")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .help("Quit SleepLess (⌘Q). Brightness and normal sleep come back straight away.")
            }
            .font(.callout)
            UpdateRows(updater: .shared)
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text("SleepLess \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") ·")
                    Link("Licence", destination: URL(string: "https://github.com/Weta-Technologies/SleepLess/blob/main/LICENSE")!)
                        .help("The SleepLess licence agreement (freeware, all rights reserved).")
                    Text("·")
                    Link("Privacy", destination: URL(string: "https://github.com/Weta-Technologies/SleepLess/blob/main/PRIVACY.md")!)
                        .help("The privacy policy: SleepLess collects nothing.")
                    Text("·")
                    Link("GitHub", destination: URL(string: "https://github.com/Weta-Technologies/SleepLess")!)
                        .help("Source, releases and issues on GitHub.")
                }
                Text("© 2026 Weta Technologies Limited. All rights reserved.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(width: 344)
        .animation(reduceMotion ? nil : panelEase, value: keeper.note)
        .animation(reduceMotion ? nil : panelEase, value: keeper.helperReady)
    }
}

/// Big animated glyph, a plain-English sentence about what SleepLess is doing right now — the mode, the time
/// left, which automation is holding — and the main switch, the same on/off a click on the menu-bar icon does.
struct StatusHeader: View {
    @ObservedObject var keeper: Keeper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOn: Bool { keeper.isOn }

    private var title: String { isOn ? "Keeping your Mac awake" : "Your Mac sleeps normally" }

    /// The mode by hand, or — with nothing on by hand — the automation holding (or paused by a click).
    private var mode: String {
        let s = keeper.s
        switch (s.screenOn, s.lidOn) {
        case (true, true): return "Screen stays on · lid can be closed"
        case (true, false): return s.screenSleeps ? "Mac stays awake, screen may sleep" : s.dims ? "Screen stays on, dims when idle" : "Screen stays on"
        case (false, true): return keeper.lidActive ? "Even with the lid closed" : "Starting lid-closed mode…"
        case (false, false):
            if !keeper.reasons.isEmpty { return Automation.sentence(keeper.reasons) }
            if !keeper.paused.isEmpty { return Automation.sentence(keeper.paused, prefix: "Paused while ") }
            return "Switch on, or pick a mode below"
        }
    }

    /// The automation holding alongside a mode that is on by hand.
    private var reason: String { keeper.s.screenOn || keeper.s.lidOn ? Automation.sentence(keeper.reasons, prefix: "while ") : "" }

    private var countdown: ClosedRange<Date>? {
        guard keeper.s.screenOn || keeper.s.lidOn, let offAt = keeper.s.offAt, offAt > .now else { return nil }
        return Date.now...offAt
    }

    /// "Screen stays on · 1:12:05 left · while Video Call is running" — the countdown ticks by itself.
    private var detail: Text {
        var text = Text(mode)
        if let countdown { text = text + Text(" · ") + Text(timerInterval: countdown, countsDown: true) + Text(" left") }
        if !reason.isEmpty { text = text + Text(" · " + reason) }
        return text
    }

    var body: some View {
        HStack(spacing: 12) {
            HeaderGlyph(icon: keeper.icon, isOn: isOn)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                detail.font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : panelEase, value: title + mode + reason)
            .layoutPriority(1)
            Spacer(minLength: 8)
            Toggle("SleepLess", isOn: Binding(get: { isOn }, set: { _ in withAnimation(reduceMotion ? nil : panelEase) { keeper.toggleAwake() } }))
                .labelsHidden().toggleStyle(.switch)
                .help("Turn SleepLess on or off — the same as clicking the menu-bar icon. Turning it back on brings back the modes you had on.")
                .accessibilityLabel("SleepLess")
                .accessibilityHint("Turns everything off, or brings back the modes you last had on")
        }
    }
}

/// Whether the panel is on screen. The status item flips it, so the live glyph only follows the 4 fps
/// menu-bar animation while the popover is open (the hidden panel costs nothing).
private struct PanelVisibleKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var panelVisible: Bool {
        get { self[PanelVisibleKey.self] }
        set { self[PanelVisibleKey.self] = newValue }
    }
}

/// The menu-bar glyph, drawn large from the same frame the menu bar shows. Grey when off; the icon's
/// sunrise colours with a soft glow while SleepLess is keeping the Mac awake.
struct HeaderGlyph: View {
    let icon: MenuIcon
    let isOn: Bool
    @Environment(\.panelVisible) private var visible

    var body: some View {
        if visible {
            LiveGlyph(icon: icon, isOn: isOn)
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }
}

struct LiveGlyph: View {
    @ObservedObject var icon: MenuIcon
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let glyph = Image(nsImage: MenuIcon.draw(icon.frame, side: 44)).renderingMode(.template)
        ZStack {
            glyph.foregroundStyle(.secondary)
            glyph.foregroundStyle(Sunrise.gradient)
                .shadow(color: Sunrise.sun.opacity(0.7), radius: 6)
                .opacity(isOn ? 1 : 0)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: isOn)
        .accessibilityHidden(true)
    }
}

/// Battery level, shown beside the safety rules it feeds into.
struct BatteryLabel: View {
    let battery: Power.Battery

    private var symbol: String {
        if battery.onAC { return "battery.100percent.bolt" }
        switch battery.percent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    var body: some View {
        Label("\(battery.percent)%", systemImage: symbol)
            .font(.caption).monospacedDigit()
            .foregroundStyle(battery.percent <= 20 && !battery.onAC ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .help(battery.onAC ? "Charging" : "On battery")
            .accessibilityLabel("Battery \(battery.percent) percent, \(battery.onAC ? "charging" : "not charging")")
    }
}

/// An inline, dismissible message: why something turned off or an install error (warning), the timer
/// finishing (info), or the first-run tip.
struct Notice: View {
    enum Kind { case warning, info, tip }
    let text: String
    let kind: Kind
    let dismiss: () -> Void

    private var color: Color { kind == .warning ? .orange : .accentColor }
    private var symbol: String {
        switch kind {
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "checkmark.circle.fill"
        case .tip: return "lightbulb.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.12)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind == .warning ? "Warning" : "Notice"): \(text)")
    }
}

/// A mode: icon tile, title, one-line explanation and its switch, plus any rows that belong to it.
struct ModeCard<Rows: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let help: String
    var disabled = false   // the switch can't be flipped (its helper isn't set up)
    @Binding var isOn: Bool
    @ViewBuilder let rows: Rows
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconTile(symbol: symbol, tint: tint, lit: isOn)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).help(help).disabled(disabled)
            }
            rows
        }
        .padding(12)
        .background(shape.fill(isOn ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.045)))
        .overlay(shape.strokeBorder(isOn ? Color.accentColor.opacity(contrast == .increased ? 0.6 : 0.25)
                                         : Color.primary.opacity(contrast == .increased ? 0.4 : 0.08)))
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }
}

/// System Settings-style coloured square with a white symbol; grey while its mode is off.
struct IconTile: View {
    let symbol: String
    let tint: Color
    let lit: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if #available(macOS 14, *), !reduceMotion {
                Image(systemName: symbol).symbolEffect(.bounce, value: lit)
            } else {
                Image(systemName: symbol)
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(lit ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.gray.gradient)))
        .accessibilityHidden(true)
    }
}

/// Title (+ optional subtitle) on the left, a small switch pinned to the right edge. An accent-coloured subtitle
/// marks a rule that is holding right now.
struct SwitchRow: View {
    let title: String
    var subtitle: String?
    var live = false
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(live ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).help(help)
        }
    }
}

/// A collapsible section's header: chevron, title, a one-line summary of what is inside (accent-coloured while
/// the section is doing something right now), and room for something on the right.
struct DisclosureRow<Trailing: View>: View {
    let title: String
    let summary: String
    var symbol: String?
    var live = false
    let help: String
    @Binding var expanded: Bool
    @ViewBuilder var trailing: Trailing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : panelEase) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 12)
                if let symbol { Image(systemName: symbol).foregroundStyle(live ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)).frame(width: 16) }
                Text(title).font(.callout.weight(.medium))
                Text(summary).font(.caption).foregroundStyle(live ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .lineLimit(1).truncationMode(.tail)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : panelEase, value: summary)
                Spacer(minLength: 8)
                trailing
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel("\(title): \(summary)")
        .accessibilityValue(expanded ? "expanded" : "collapsed")
        .accessibilityAddTraits(.isButton)
    }
}

extension DisclosureRow where Trailing == EmptyView {
    init(title: String, summary: String, symbol: String? = nil, live: Bool = false, help: String, expanded: Binding<Bool>) {
        self.init(title: title, summary: summary, symbol: symbol, live: live, help: help, expanded: expanded) { EmptyView() }
    }
}
