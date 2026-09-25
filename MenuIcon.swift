import AppKit

/// Lidless-style menu-bar glyph (a lid with a horizon line), animated: rays rise like a sunrise when
/// SleepLess starts keeping the Mac awake, shimmer while it stays on, and set again when it stops.
/// A sun comes up over the horizon in lid-closed mode. Frames are only drawn while something moves,
/// never while the screens are asleep (e.g. lid closed), and never under Reduce Motion (one still frame).
@MainActor final class MenuIcon: ObservableObject {
    /// One drawn frame of the glyph. The panel re-draws the current one at a larger size.
    struct Frame: Equatable {
        var rise: CGFloat = 0      // 0 = rays down (off) … 1 = full sunrise
        var sun: CGFloat = 0       // 0 = below the horizon … 1 = risen (lid-closed mode)
        var phase: CGFloat = 0     // shimmer wave position
        var shimmer: CGFloat = 0.15 // shimmer amplitude (fraction of ray length); 0 under Reduce Motion
    }

    @Published private(set) var frame = Frame()
    @Published private(set) var image = MenuIcon.draw(Frame())
    private var wantRise: CGFloat = 0, wantSun: CGFloat = 0
    private var screensAsleep = false
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var timer: Timer?
    private static let fps: CGFloat = 20        // sunrise / sunset
    private static let idleFPS: CGFloat = 6     // ponytail: steady shimmer at 6 fps keeps always-on cost ~1% CPU (15 fps was ~4%)

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.screensAsleep = asleep; self.run() }
            }
        }
        center.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                self.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self.run()
            }
        }
    }

    func show(screen: Bool, lid: Bool) {
        let rise: CGFloat = screen || lid ? 1 : 0, sun: CGFloat = lid ? 1 : 0
        guard rise != wantRise || sun != wantSun else { return }
        wantRise = rise
        wantSun = sun
        run()
    }

    private func run() {
        if reduceMotion {   // no sunrise, no shimmer: straight to the final frame, no timer
            timer?.invalidate()
            timer = nil
            render(Frame(rise: wantRise, sun: wantSun, phase: 0, shimmer: 0))
            return
        }
        let transitioning = frame.rise != wantRise || frame.sun != wantSun
        let moving = !screensAsleep && (transitioning || wantRise == 1)
        let interval = 1 / Double(transitioning ? Self.fps : Self.idleFPS)
        if !moving || timer?.timeInterval != interval {
            timer?.invalidate()
            timer = nil
        }
        guard moving, timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { self.step() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func step() {
        let dt = CGFloat(timer?.timeInterval ?? 1 / Double(Self.fps))
        var next = frame
        next.rise = Self.approach(next.rise, wantRise, by: dt / 0.8)   // full sunrise in 0.8 s
        next.sun = Self.approach(next.sun, wantSun, by: dt / 0.5)
        next.phase += dt * 2 * .pi / 2.4                                // one shimmer wave every 2.4 s
        next.shimmer = Frame().shimmer
        render(next)
        run()   // stops the timer once settled and off
    }

    private func render(_ next: Frame) {
        guard next != frame else { return }
        frame = next
        image = Self.draw(next)
    }

    private static func approach(_ value: CGFloat, _ target: CGFloat, by step: CGFloat) -> CGFloat {
        value < target ? min(value + step, target) : max(value - step, target)
    }

    private static func ease(_ t: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func draw(rise: CGFloat, sun: CGFloat, phase: CGFloat) -> NSImage {
        draw(Frame(rise: rise, sun: sun, phase: phase))
    }

    /// Template image (macOS tints it for light/dark menu bars), `side` points square. The geometry is laid
    /// out on an 18 pt grid and scaled, so the panel can draw the same glyph large and crisp.
    static func draw(_ f: Frame, side: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            NSGraphicsContext.current?.cgContext.scaleBy(x: side / 18, y: side / 18)
            NSColor.black.set()
            let line = { (from: NSPoint, to: NSPoint) in
                let path = NSBezierPath()
                path.move(to: from)
                path.line(to: to)
                path.lineWidth = 1.5
                path.lineCapStyle = .round
                path.stroke()
            }
            let lid = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 1.75, width: 14.5, height: 14.5), xRadius: 4.5, yRadius: 4.5)
            lid.lineWidth = 1.5
            lid.stroke()

            let horizon = NSPoint(x: 9, y: 5)
            line(NSPoint(x: 5.5, y: horizon.y), NSPoint(x: 12.5, y: horizon.y))

            if f.sun > 0.01 {   // a disc climbing up from behind the horizon
                let r: CGFloat = 2.3, centerY = horizon.y - r * (1 - ease(f.sun))
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: 0, y: horizon.y, width: 18, height: 18)).addClip()
                NSBezierPath(ovalIn: NSRect(x: horizon.x - r, y: centerY - r, width: 2 * r, height: 2 * r)).fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            let origin = NSPoint(x: 9, y: 6.25)   // rays fan out from just above the horizon, clear of its ends
            for (i, degrees) in [155.0, 122, 90, 58, 25].enumerated() {
                let fromCenter = CGFloat(abs(i - 2))                              // centre ray rises first, sets last
                let grow = ease((f.rise - fromCenter * 0.2) / 0.6)
                let shimmer = 1 - f.shimmer + f.shimmer * sin(f.phase - CGFloat(i) * 0.9)   // a wave running across the rays
                let length = 2.4 * grow * shimmer
                guard length > 0.15 else { continue }
                let angle = degrees * .pi / 180, inner: CGFloat = 3.2
                let point = { (r: CGFloat) in NSPoint(x: origin.x + cos(angle) * r, y: origin.y + sin(angle) * r) }
                line(point(inner), point(inner + length))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
