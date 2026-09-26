import AppKit
import SwiftUI

/// `SleepLess --shots <dir>`: the panel in its main states and the right-click menu, light and dark, as PNGs — for
/// the README and polish passes. Sample state only: no status item, no timers, nothing on the Mac touched (the menu
/// shows at the top-left of the screen for half a second); the process exits once the files are written. The
/// panel's disclosure keys are set per state and put back afterwards, so run it while SleepLess is quit (or from a
/// copy with another bundle identifier).
@MainActor enum Shots {
    static func run(dir: String) -> Never {
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: dir)
        try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // AppKit gives controls their accent colours only while the app is active: say it is, without activating it.
        if let m = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.isActive)) {
            method_setImplementation(m, imp_implementationWithBlock({ (_: AnyObject) -> Bool in true } as @convention(block) (AnyObject) -> Bool))
        }
        let call = SampleApp.call.ref, slides = SampleApp.slides.ref
        AppRef.sampleIcon = SampleApp.icon   // the made-up apps get made-up icons (this process only)
        var screen = Settings(); screen.screenOn = true; screen.dims = true
        var lid = Settings(); lid.lidOn = true; lid.offAfter = 60; lid.offAt = Date().addingTimeInterval(38 * 60); lid.offFrom = Date().addingTimeInterval(-22 * 60)
        var auto = Settings(); auto.appsOn = true; auto.apps = [call, slides]; auto.scheduleOn = true; auto.screenSleeps = true
        var more = Settings(); more.screenOn = true; more.offAtMinute = 17 * 60 + 30; more.offAt = Clock.next(minute: 17 * 60 + 30, after: Date()); more.offFrom = Date()
        more.timeInMenuBar = true; more.notify = true; more.hotKey = HotKey(keyCode: 1, modifiers: HotKey.carbon([.control, .option, .command]), key: "S"); more.appsOn = true; more.apps = [call]
        var readme = Settings(); readme.screenOn = true; readme.offAfter = 60; readme.offAt = Date().addingTimeInterval(52 * 60); readme.offFrom = Date().addingTimeInterval(-8 * 60)
        readme.timeInMenuBar = true; readme.appsOn = true; readme.apps = [call, slides]; readme.hotKey = more.hotKey
        let charging = Power.Battery(percent: 72, onAC: true)
        let states: [(name: String, keeper: Keeper, tip: Bool, safety: Bool, automations: Bool, more: Bool)] = [
            ("readme", Keeper(shots: readme, battery: charging, helperReady: true, reasons: [.app(call)]), false, false, false, false),
            ("setup", Keeper(shots: Settings(), battery: charging, helperReady: false), true, false, false, false),
            ("off", Keeper(shots: Settings(), battery: charging, helperReady: true), false, false, false, false),
            ("screen", Keeper(shots: screen, battery: charging, helperReady: true), false, false, false, false),
            ("lid", Keeper(shots: lid, battery: charging, helperReady: true, lidActive: true), false, true, false, false),
            ("automations", Keeper(shots: auto, battery: charging, helperReady: true, reasons: [.app(call)]), false, false, true, false),
            ("more", Keeper(shots: more, battery: charging, helperReady: true, reasons: [.app(call)]), false, false, false, true),
            ("update", Keeper(shots: Settings(), battery: Power.Battery(percent: 18, onAC: false), helperReady: true,   // last: the sample offer stays
                              note: "Lid-closed mode turned off: battery at 18%."), false, false, false, false),
        ]
        let defaults = UserDefaults.standard
        let keys = ["tapHintSeen", "safetyExpanded", "automationsExpanded", "moreExpanded"]
        let kept = keys.map { ($0, defaults.object(forKey: $0)) }
        for state in states {
            if state.name == "update" { Updater.shared.offerSample() }
            defaults.set(!state.tip, forKey: "tapHintSeen")
            defaults.set(state.safety, forKey: "safetyExpanded")
            defaults.set(state.automations, forKey: "automationsExpanded")
            defaults.set(state.more, forKey: "moreExpanded")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))   // the glyph's sunrise settles
            for dark in [false, true] { write(Panel(keeper: state.keeper), as: "\(state.name)-\(dark ? "dark" : "light")", dark: dark, to: out) }
        }
        for (key, value) in kept { defaults.set(value, forKey: key) }
        for dark in [false, true] { writeMenu(states[0].keeper, as: "menu-\(dark ? "dark" : "light")", dark: dark, to: out) }
        print("Wrote \(states.count * 2) panel shots and 2 menu shots to \(out.path)")
        exit(0)
    }

    /// The right-click menu: popped up at the top-left of the screen for a moment and captured from its own window
    /// (a process may always capture its own windows), then dismissed.
    private static var menu: NSMenu?   // the one being captured (a static, so the timer's closure captures nothing)

    /// The menu is translucent: the window server blurs and tints whatever is behind it, and a capture of the window
    /// on its own is just the tint. So a plain window in the window-background colour goes underneath first, and the
    /// shot is the screen area of the menu as composited — the menu over that window, the way it looks over any
    /// ordinary window. (Without Screen Recording permission the capture holds this process's windows only.)
    private static func writeMenu(_ keeper: Keeper, as name: String, dark: Bool, to dir: URL) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        NSApp.appearance = appearance
        let menu = StatusMenu(keeper: keeper, openSettings: {}, closed: {}).menu()
        Self.menu = menu
        let top = NSScreen.main.map { NSPoint(x: $0.visibleFrame.minX + 24, y: $0.visibleFrame.maxY - 8) } ?? NSPoint(x: 24, y: 900)
        let backdrop = ShotWindow(contentRect: NSRect(x: top.x - 40, y: top.y - 640, width: 760, height: 660), styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.appearance = appearance
        appearance.performAsCurrentDrawingAppearance { backdrop.backgroundColor = .windowBackgroundColor }
        backdrop.level = .floating
        backdrop.orderFrontRegardless()
        let timer = Timer(timeInterval: 0.5, repeats: false) { _ in
            MainActor.assumeIsolated {
                if let image = ownMenuScreenImage() {
                    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("\(name).png"))
                } else {
                    NSLog("SleepLess --shots: the menu could not be captured")
                }
                Self.menu?.cancelTracking()
            }
        }
        RunLoop.main.add(timer, forMode: .common)   // fires inside the menu's tracking loop
        menu.popUp(positioning: nil, at: top, in: nil)
        backdrop.orderOut(nil)
        Self.menu = nil
    }

    /// The screen area of this process's menu window (the only one of its windows at the menu level), as composited.
    private static func ownMenuScreenImage() -> CGImage? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let mine = windows.first { ($0[kCGWindowOwnerPID as String] as? Int32) == getpid() && ($0[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.popUpMenuWindow)) }
        guard let id = mine?[kCGWindowNumber as String] as? Int, let window = NSApp.window(withWindowNumber: id), let primary = NSScreen.screens.first else { return nil }
        let frame = window.frame   // AppKit's origin is the primary screen's bottom-left; the window server's is its top-left
        let area = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        return CGWindowListCreateImage(area, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
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

/// The apps in the sample state: made up, so no real app is named, with icons drawn here (a symbol on a gradient tile).
enum SampleApp: String, CaseIterable {
    case call = "com.example.videocall", slides = "com.example.slides"

    var ref: AppRef { AppRef(id: rawValue, name: self == .call ? "Video Call" : "Slides") }

    static func icon(for id: String) -> NSImage? {
        guard let app = SampleApp(rawValue: id) else { return nil }
        let symbol = app == .call ? "video.fill" : "play.rectangle.fill"
        let tint = app == .call ? NSColor.systemTeal : NSColor.systemOrange
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let tile = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
            NSGradient(starting: tint.blended(withFraction: 0.3, of: .white) ?? tint, ending: tint)?.draw(in: tile, angle: -90)
            let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
            guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return true }
            let white = NSImage(size: glyph.size, flipped: false) { r in glyph.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true }
            white.draw(in: NSRect(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2, width: glyph.size.width, height: glyph.size.height))
            return true
        }
    }
}
