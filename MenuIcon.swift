import AppKit

/// Lidless-style menu-bar glyph (a lid with a horizon line), animated: rays rise like a sunrise when
/// SleepLess starts keeping the Mac awake, shimmer while it stays on, and set again when it stops.
/// A sun comes up over the horizon in lid-closed mode. Frames are only drawn while something moves,
/// and never while the screens are asleep (e.g. lid closed).
@MainActor final class MenuIcon: ObservableObject {
    @Published private(set) var image = MenuIcon.draw(rise: 0, sun: 0, phase: 0)
    private var rise: CGFloat = 0, sun: CGFloat = 0, phase: CGFloat = 0
    private var wantRise: CGFloat = 0, wantSun: CGFloat = 0
    private var screensAsleep = false
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
    }

    func show(screen: Bool, lid: Bool) {
        let rise: CGFloat = screen || lid ? 1 : 0, sun: CGFloat = lid ? 1 : 0
        guard rise != wantRise || sun != wantSun else { return }
        wantRise = rise
        wantSun = sun
        run()
    }

    private func run() {
        let transitioning = rise != wantRise || sun != wantSun
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
        rise = Self.approach(rise, wantRise, by: dt / 0.8)   // full sunrise in 0.8 s
        sun = Self.approach(sun, wantSun, by: dt / 0.5)
        phase += dt * 2 * .pi / 2.4                           // one shimmer wave every 2.4 s
        image = Self.draw(rise: rise, sun: sun, phase: phase)
        run()   // stops the timer once settled and off
    }

    private static func approach(_ value: CGFloat, _ target: CGFloat, by step: CGFloat) -> CGFloat {
        value < target ? min(value + step, target) : max(value - step, target)
    }

    private static func ease(_ t: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// 18 pt template image, so macOS tints it for light/dark menu bars.
    static func draw(rise: CGFloat, sun: CGFloat, phase: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
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

            if sun > 0.01 {
                let disc = NSBezierPath()
                disc.appendArc(withCenter: horizon, radius: 2.3 * ease(sun), startAngle: 0, endAngle: 180)
                disc.close()
                disc.fill()
            }

            let origin = NSPoint(x: 9, y: 6.25)   // rays fan out from just above the horizon, clear of its ends
            for (i, degrees) in [155.0, 122, 90, 58, 25].enumerated() {
                let fromCenter = CGFloat(abs(i - 2))                          // centre ray rises first
                let grow = ease((rise - fromCenter * 0.2) / 0.6)
                let shimmer = 0.8 + 0.2 * sin(phase - CGFloat(i) * 0.9)       // a wave running across the rays
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
