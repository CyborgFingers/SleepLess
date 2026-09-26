import AppKit
import SwiftUI

/// `SleepLess --shots <dir>`: the panel in its main states, light and dark, as PNGs — for the README and polish
/// passes. Sample state only: no status item, no timers, nothing on the Mac touched; the process exits once the
/// files are written. The panel's two disclosure keys are set per state and put back afterwards, so run it while
/// SleepLess is quit (or from a copy with another bundle identifier).
@MainActor enum Shots {
    static func run(dir: String) -> Never {
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: dir)
        try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // AppKit gives controls their accent colours only while the app is active: say it is, without activating it.
        if let m = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.isActive)) {
            method_setImplementation(m, imp_implementationWithBlock({ (_: AnyObject) -> Bool in true } as @convention(block) (AnyObject) -> Bool))
        }
        var screen = Settings(); screen.screenOn = true; screen.dims = true
        var lid = Settings(); lid.lidOn = true; lid.offAfter = 60; lid.offAt = Date().addingTimeInterval(38 * 60)
        let charging = Power.Battery(percent: 72, onAC: true)
        let states: [(name: String, keeper: Keeper, tip: Bool, safety: Bool)] = [
            ("setup", Keeper(shots: Settings(), battery: charging, helperReady: false), true, false),
            ("off", Keeper(shots: Settings(), battery: charging, helperReady: true), false, false),
            ("screen", Keeper(shots: screen, battery: charging, helperReady: true), false, false),
            ("lid", Keeper(shots: lid, battery: charging, helperReady: true, lidActive: true), false, true),
            ("update", Keeper(shots: Settings(), battery: Power.Battery(percent: 18, onAC: false), helperReady: true,
                              note: "Lid-closed mode turned off: battery at 18%."), false, false),
        ]
        let defaults = UserDefaults.standard
        let kept = ["tapHintSeen", "safetyExpanded"].map { ($0, defaults.object(forKey: $0)) }
        for state in states {
            if state.name == "update" { Updater.shared.offerSample() }
            defaults.set(!state.tip, forKey: "tapHintSeen")
            defaults.set(state.safety, forKey: "safetyExpanded")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))   // the glyph's sunrise settles
            for dark in [false, true] { write(Panel(keeper: state.keeper), as: "\(state.name)-\(dark ? "dark" : "light")", dark: dark, to: out) }
        }
        for (key, value) in kept { defaults.set(value, forKey: key) }
        print("Wrote \(states.count * 2) panel shots to \(out.path)")
        exit(0)
    }

    /// Ordered in but off every display, and key: AppKit then draws the controls in their active look.
    private final class ShotWindow: NSWindow { override var canBecomeKey: Bool { true } }

    /// The view at its natural size on the window background, in the light or dark appearance.
    private static func write<V: View>(_ view: V, as name: String, dark: Bool, to dir: URL) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let window = ShotWindow(contentRect: NSRect(origin: NSPoint(x: -30000, y: -30000), size: host.fittingSize),
                                styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.orderFrontRegardless()
        window.makeKey()
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance { NSColor.windowBackgroundColor.setFill(); host.bounds.fill() }
        NSGraphicsContext.restoreGraphicsState()
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
