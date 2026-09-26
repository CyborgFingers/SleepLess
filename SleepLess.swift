import SwiftUI
import IOKit.pwr_mgt

// SleepLess — keep the screen on (optionally dimmed) and/or keep the Mac awake with the lid closed, with
// safety cut-offs, an auto-off timer and launch at login.
// The menu-bar item lives in StatusItem.swift, the panel UI in Panel.swift / PanelSections.swift.

@main struct SleepLessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        if CommandLine.arguments.contains("--selftest") { selfTest() }
        if let i = CommandLine.arguments.firstIndex(of: "--shots"), i + 1 < CommandLine.arguments.count { Shots.run(dir: CommandLine.arguments[i + 1]) }
    }

    var body: some Scene {
        SwiftUI.Settings { EmptyView() }   // no windows of its own; the status item owns the panel
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Updater.shared.testRun { return Updater.shared.start() }   // --update-test: only the updater, on a copy of the app
        statusItem = StatusItemController(keeper: Keeper())
        Updater.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// `SleepLess.app/Contents/MacOS/SleepLess --selftest` checks the OS hooks still work after macOS updates
/// (briefly nudges brightness) and the pure menu-bar click logic. The root helper is covered by test-helper.sh.
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
    if let keyboard = KeyboardLight.get() {   // keyboard backlight (lid-shut darkening): 0 and back
        KeyboardLight.set(.init(brightness: 0, auto: false))
        usleep(300_000)
        let off = KeyboardLight.get()?.brightness ?? -1
        KeyboardLight.set(keyboard)
        precondition(off == 0, "FAIL: keyboard backlight set 0, read \(off)")
    }

    // Menu-bar tap: on → off remembering the modes, off → those modes back; first tap = screen awake.
    let off = Keeper.tapPlan(screenOn: true, lidOn: true, remembered: TapRestore())
    precondition(!off.screen && !off.lid && off.remember == TapRestore(screen: true, lid: true), "FAIL: tap should turn both modes off and remember them")
    let back = Keeper.tapPlan(screenOn: false, lidOn: false, remembered: off.remember)
    precondition(back.screen && back.lid && back.remember == off.remember, "FAIL: tap should bring both modes back")
    let first = Keeper.tapPlan(screenOn: false, lidOn: false, remembered: TapRestore())
    precondition(first.screen && !first.lid, "FAIL: first tap should turn screen awake on")
    let screenOnly = Keeper.tapPlan(screenOn: true, lidOn: false, remembered: TapRestore(screen: true, lid: true))
    precondition(screenOnly.remember == TapRestore(screen: true, lid: false), "FAIL: tap should remember only what was on")

    // Click decision: quick press = tap, held past the deadline = hold, right/⌃-click = settings.
    precondition(StatusItemController.gesture(.leftMouseDown, control: false) { true } == .tap, "FAIL: quick press should be a tap")
    precondition(StatusItemController.gesture(.leftMouseDown, control: false) { false } == .hold, "FAIL: held press should be a hold")
    precondition(StatusItemController.gesture(.rightMouseDown, control: false) { true } == .settings, "FAIL: right-click should open settings")
    precondition(StatusItemController.gesture(.leftMouseDown, control: true) { true } == .settings, "FAIL: control-click should open settings")

    Updater.selfTest()   // versions, the release feed, signatures, the swap script on a fake bundle

    print("PASS: brightness + keyboard-light round-trips, display/system sleep assertions, battery, tap/hold logic, updater (SleepDisabled now \(Power.sleepDisabled))")
    exit(0)
}
