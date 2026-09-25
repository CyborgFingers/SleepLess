import AppKit

/// The menu-bar glyph: a screen with the app icon's sunrise inside. Off is a hollow sun resting on the bottom bezel.
/// Turning on, the sun climbs in and five rays fan out centre-first (0.7 s); while it stays on the rays breathe
/// slowly; turning off runs it back (0.55 s). Lid-closed mode lifts the sun to the middle of the screen as a full
/// disc. Frames are only drawn while something moves (30 fps in a transition, 4 fps breathing), never while the
/// screens are asleep, and Reduce Motion gets one still frame per state. It is a template image, so macOS tints it
/// for light and dark menu bars.
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
    private var lidShut = false         // lid closed with the screen kept dark: nobody can see the menu bar
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

    /// Pauses the animation while the lid is shut (the screen stays technically awake, so `screensAsleep` never fires).
    func setLidShut(_ shut: Bool) {
        guard shut != lidShut else { return }
        lidShut = shut
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
        let moving = !screensAsleep && !lidShut && (transitioning || wantRise == 1)
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
    /// panel's larger size. The screen frame is a thinner stroke (1 pt) than the sun (1.5 pt), so the sun stays the hero.
    static func draw(_ f: Frame, side: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            cg.scaleBy(x: side / 18, y: side / 18)
            let s = max(abs(cg.ctm.a), 0.001)                  // device pixels per grid unit
            let framePx = max(1, s.rounded()), sunPx = max(1, (1.5 * s).rounded())   // 1 px / 2 px at 1x, 2 px / 3 px at 2x
            let fw = framePx / s, w = sunPx / s
            let snap = { (v: CGFloat, px: CGFloat) in Int(px) % 2 == 1 ? (floor(v * s) + 0.5) / s : (v * s).rounded() / s }   // stroke centre lines
            let radius = { (v: CGFloat) -> CGFloat in          // a disc whose vertical ray shares the sun stroke's pixel parity
                let d = (2 * v * s).rounded()
                return (Int(d) % 2 == 1) == (Int(sunPx) % 2 == 1) ? d / (2 * s) : (d - 1) / (2 * s)
            }
            let stroke = { (path: NSBezierPath, width: CGFloat) in
                path.lineWidth = width
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            let line = { (a: NSPoint, b: NSPoint) in
                let path = NSBezierPath()
                path.move(to: a)
                path.line(to: b)
                stroke(path, w)
            }

            NSColor.black.set()
            // The screen: a landscape display frame, the same in every state.
            let x0 = snap(0.5, framePx), x1 = snap(17.5, framePx), y0 = snap(2.5, framePx), y1 = snap(15.5, framePx)
            stroke(NSBezierPath(roundedRect: NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0), xRadius: 2.5, yRadius: 2.5), fw)
            let left = x0 + fw / 2, right = x1 - fw / 2, bottom = y0 + fw / 2, top = y1 - fw / 2   // inside the bezel

            let lift = easeInOut(f.sun), climb = easeOut(f.rise / 0.6)   // the sun climbs in over the first 60 % of the sunrise
            let cx = snap(9, sunPx)                            // the sun and its vertical ray sit on cx
            let r = radius(3.75 - lift)                        // half-disc on the bottom bezel … a smaller full disc above it
            let cyOn = snap(bottom, sunPx), cyLid = snap(bottom + 3.75, sunPx)
            let cy = cyOn + (cyLid - cyOn) * lift
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: left, y: bottom, width: right - left, height: top - bottom)).addClip()   // nothing shows outside the screen
            if climb < 0.999 {                                 // hollow sun = off
                stroke(NSBezierPath(ovalIn: NSRect(x: cx - r + w / 2, y: cy - r + w / 2, width: 2 * r - w, height: 2 * r - w)), w)
            }
            if climb > 0.001 {
                let risen = cy - r + r * climb                 // from fully below the bezel up to its resting height
                NSBezierPath(ovalIn: NSRect(x: cx - r, y: risen - r, width: 2 * r, height: 2 * r)).fill()
            }
            NSGraphicsContext.restoreGraphicsState()

            let breath = 1 - f.shimmer * (1 - cos(f.phase)) / 2
            NSColor(white: 0, alpha: breath).set()
            let inner = r + 1 + lift, length = 2.25 - 0.25 * lift   // the lifted sun gets more air round it
            for (i, degrees) in rayAngles.enumerated() {
                let fromCentre = CGFloat(abs(i - 2))          // centre ray first, outer rays last (and first back in)
                let grow = min(overshoot((f.rise - 0.35 - fromCentre * 0.12) / 0.35), 1.1)
                let ray = length * grow
                guard ray > 0.2 else { continue }
                let angle = degrees * .pi / 180
                let point = { (d: CGFloat) in NSPoint(x: cx + cos(angle) * d, y: cy + sin(angle) * d) }
                line(point(inner), point(inner + ray))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
