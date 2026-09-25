import AppKit

/// The menu-bar glyph: the app icon's sunrise. Off is a hollow sun on the horizon. Turning on, the sun climbs in
/// and five rays fan out centre-first (0.7 s); while it stays on the rays breathe slowly; turning off runs it back
/// (0.55 s). Lid-closed mode lifts the sun clear of the horizon as a full disc. Frames are only drawn while something
/// moves (30 fps in a transition, 4 fps breathing), never while the screens are asleep, and Reduce Motion gets one
/// still frame per state. It is a template image, so macOS tints it for light and dark menu bars.
@MainActor final class MenuIcon: ObservableObject {
    /// One drawn frame of the glyph. The panel re-draws the current one at a larger size.
    struct Frame: Equatable {
        var rise: CGFloat = 0       // 0 = off … 1 = on: sun risen, rays out (the on/off transition's progress)
        var sun: CGFloat = 0        // 0 = sun on the horizon … 1 = lifted clear of it (lid-closed mode)
        var phase: CGFloat = 0      // breathing wave position, radians
        var shimmer: CGFloat = 0.45 // breathing depth: the rays fade to 1 - shimmer at the trough; 0 under Reduce Motion
    }

    @Published private(set) var frame = Frame()
    @Published private(set) var image = MenuIcon.draw(Frame())
    private var wantRise: CGFloat = 0, wantSun: CGFloat = 0
    private var from = Frame(), started = Date.distantPast   // the transition in flight starts from `from` at `started`
    private var screensAsleep = false
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var timer: Timer?

    static let onDuration: TimeInterval = 0.7, offDuration: TimeInterval = 0.55, lidDuration: TimeInterval = 0.5
    static let breathPeriod: TimeInterval = 5     // one slow breath of the rays
    static let fps: Double = 30                   // transitions
    static let idleFPS: Double = 4                // ponytail: 4 fps breathing ≈ 0.6 % CPU always-on, from the 6 fps ≈ 0.9 % measurement

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
        from = frame        // a toggle mid-transition turns round from wherever it got to
        started = Date()
        run()
    }

    private var transitioning: Bool { frame.rise != wantRise || frame.sun != wantSun }

    private func run() {
        if reduceMotion {   // no sunrise, no breathing: straight to the final frame, no timer
            timer?.invalidate()
            timer = nil
            render(Frame(rise: wantRise, sun: wantSun, phase: 0, shimmer: 0))
            return
        }
        let moving = !screensAsleep && (transitioning || wantRise == 1)
        let interval = 1 / (transitioning ? Self.fps : Self.idleFPS)
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
        var next = frame
        if transitioning {   // clock-driven, so timer jitter never stretches the sunrise
            let duration = wantRise > from.rise ? Self.onDuration : wantRise < from.rise ? Self.offDuration : Self.lidDuration
            let p = CGFloat(Date().timeIntervalSince(started) / duration)
            next.rise = p < 1 ? from.rise + (wantRise - from.rise) * p : wantRise   // land exactly, so it settles
            next.sun = p < 1 ? from.sun + (wantSun - from.sun) * p : wantSun
            next.phase = 0   // rays at full strength through the transition; the breathing starts from there
        } else {
            next.phase = (next.phase + 2 * .pi / (Self.breathPeriod * Self.idleFPS)).truncatingRemainder(dividingBy: 2 * .pi)
        }
        next.shimmer = Frame().shimmer
        render(next)
        run()   // stops the timer once settled and off
    }

    private func render(_ next: Frame) {
        guard next != frame else { return }
        frame = next
        image = Self.draw(next)
    }

    static func draw(rise: CGFloat, sun: CGFloat, phase: CGFloat) -> NSImage {
        draw(Frame(rise: rise, sun: sun, phase: phase))
    }

    // MARK: Drawing

    private static func clamp(_ t: CGFloat) -> CGFloat { min(max(t, 0), 1) }
    private static func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - clamp(t), 3) }
    private static func easeInOut(_ t: CGFloat) -> CGFloat { let t = clamp(t); return t < 0.5 ? 2 * t * t : 1 - pow(2 - 2 * t, 2) / 2 }
    private static func overshoot(_ t: CGFloat) -> CGFloat { let u = clamp(t) - 1; return 1 + u * u * (2.4 * u + 1.4) }   // ease-out-back

    private static let rayAngles: [CGFloat] = [25, 57.5, 90, 122.5, 155]   // the app icon's five-ray fan, degrees

    /// Template image, `side` points square. The geometry is laid out on an 18-unit grid and every stroke, disc and
    /// centre is snapped to the device pixels of the context it is drawn into, so it stays crisp at 1x, 2x and at the
    /// panel's larger size.
    static func draw(_ f: Frame, side: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            cg.scaleBy(x: side / 18, y: side / 18)
            let s = max(abs(cg.ctm.a), 0.001)                  // device pixels per grid unit
            let wPx = max(1, (1.5 * s).rounded())              // 1.5 pt stroke: 2 px at 1x, 3 px at 2x
            let w = wPx / s, odd = Int(wPx) % 2 == 1
            let snap = { (v: CGFloat) in odd ? (floor(v * s) + 0.5) / s : (v * s).rounded() / s }   // stroke centre lines
            let radius = { (v: CGFloat) -> CGFloat in          // a disc whose vertical ray shares the stroke's pixel parity
                let d = (2 * v * s).rounded()
                return (Int(d) % 2 == 1) == odd ? d / (2 * s) : (d - 1) / (2 * s)
            }
            let line = { (a: NSPoint, b: NSPoint) in
                let path = NSBezierPath()
                path.move(to: a)
                path.line(to: b)
                path.lineWidth = w
                path.lineCapStyle = .round
                path.stroke()
            }

            NSColor.black.set()
            let lift = easeInOut(f.sun)
            let hy = snap(5), cx = snap(9)                     // horizon; the sun and its vertical ray sit on cx
            line(NSPoint(x: cx - 7, y: hy), NSPoint(x: cx + 7, y: hy))

            let r = radius(4.4 - 1.15 * lift)                  // half-disc on the horizon … a smaller full disc above it
            let cy = hy + lift * (snap(hy + r + 1) - hy)
            let climb = easeOut(f.rise / 0.6)                  // the sun climbs in over the first 60 % of the sunrise
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: hy + w / 2, width: 18, height: 18)).addClip()   // nothing shows below the line
            if climb < 0.999 {                                 // hollow sun = off
                let ring = NSBezierPath(ovalIn: NSRect(x: cx - r + w / 2, y: cy - r + w / 2, width: 2 * r - w, height: 2 * r - w))
                ring.lineWidth = w
                ring.stroke()
            }
            if climb > 0.001 {
                let risen = cy - r + r * climb                 // from fully below the line up to its resting height
                NSBezierPath(ovalIn: NSRect(x: cx - r, y: risen - r, width: 2 * r, height: 2 * r)).fill()
            }
            NSGraphicsContext.restoreGraphicsState()

            let breath = 1 - f.shimmer * (1 - cos(f.phase)) / 2
            NSColor(white: 0, alpha: breath).set()
            for (i, degrees) in rayAngles.enumerated() {
                let fromCentre = CGFloat(abs(i - 2))          // centre ray first, outer rays last (and first back in)
                let grow = min(overshoot((f.rise - 0.35 - fromCentre * 0.12) / 0.35), 1.1)
                let length = (2.5 - 0.25 * lift) * grow
                guard length > 0.2 else { continue }
                let angle = degrees * .pi / 180, inner = r + 1.25 + lift          // the lifted sun gets more air round it
                let point = { (d: CGFloat) in NSPoint(x: cx + cos(angle) * d, y: cy + sin(angle) * d) }
                line(point(inner), point(inner + length))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
