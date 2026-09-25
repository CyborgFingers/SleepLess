// Renders assets/menubar-animation.gif and docs/assets/menubar-animation.gif from the real menu-bar glyph:
//   swiftc -O -target arm64-apple-macosx13.0 -o build/make-animation MenuIcon.swift assets/make-animation.swift && build/make-animation
// The cycle is off → on (sunrise) → one breath → lid-closed mode → off, with the engine's own timing constants,
// drawn as macOS would: the 18 pt template image tinted on a light and a dark 2x menu bar beside a few system glyphs,
// and the same frame large, as the panel header draws it.
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct MakeAnimation {
    static func main() { MainActor.assumeIsolated { render() } }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    struct Beat { let frame: MenuIcon.Frame, delay: Double, caption: String }

    /// The whole cycle as the engine plays it: transitions at `fps`, breathing at `idleFPS`.
    @MainActor static func cycle() -> [Beat] {
        var beats: [Beat] = []
        let fps = MenuIcon.fps, idle = MenuIcon.idleFPS, period = MenuIcon.breathPeriod
        func hold(_ rise: CGFloat, _ sun: CGFloat, seconds: Double, _ caption: String) {
            for i in 0..<Int(seconds * idle) {
                let phase = CGFloat(i) / CGFloat(idle) * 2 * .pi / CGFloat(period)
                beats.append(Beat(frame: MenuIcon.Frame(rise: rise, sun: sun, phase: phase), delay: 1 / idle, caption: caption))
            }
        }
        func move(_ r0: CGFloat, _ r1: CGFloat, _ s0: CGFloat, _ s1: CGFloat, seconds: Double, _ caption: String) {
            let n = Int((seconds * fps).rounded())
            for i in 1...n {
                let p = CGFloat(i) / CGFloat(n)
                beats.append(Beat(frame: MenuIcon.Frame(rise: r0 + (r1 - r0) * p, sun: s0 + (s1 - s0) * p), delay: 1 / fps, caption: caption))
            }
        }
        beats.append(Beat(frame: MenuIcon.Frame(), delay: 1.2, caption: "Off"))
        move(0, 1, 0, 0, seconds: MenuIcon.onDuration, "Keep screen awake")
        hold(1, 0, seconds: period, "Keep screen awake")
        move(1, 1, 0, 1, seconds: MenuIcon.lidDuration, "Keep awake with lid closed")
        hold(1, 1, seconds: period / 2, "Keep awake with lid closed")
        move(1, 0, 1, 0, seconds: MenuIcon.offDuration, "Off")
        beats.append(Beat(frame: MenuIcon.Frame(), delay: 1.0, caption: "Off"))
        return beats
    }

    /// A `w`×`h` point bitmap at `scale` with an AppKit context installed.
    static func bitmap(_ w: Int, _ h: Int, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(CGFloat(w) * scale), height: Int(CGFloat(h) * scale), bitsPerComponent: 8,
                            bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        draw(ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    /// What macOS does with a template image: keep its alpha, replace its colour.
    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))!
    }

    /// A 180 pt mock menu bar at 2x: the glyph, then a few system glyphs and the clock.
    static func menuBar(_ glyph: NSImage, dark: Bool) -> CGImage {
        bitmap(180, 24, scale: 2) { _ in
            let ink = NSColor(white: dark ? 1 : 0, alpha: 0.85)
            var x: CGFloat = 12
            for image in [glyph, symbol("moon.fill"), symbol("wifi"), symbol("battery.100")] {
                tinted(image, ink).draw(in: NSRect(x: x.rounded(), y: ((24 - image.size.height) / 2).rounded(), width: image.size.width, height: image.size.height))
                x += image.size.width + 14
            }
            NSAttributedString(string: "Thu 9:41 AM", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: ink]).draw(at: NSPoint(x: x + 4, y: 4))
        }
    }

    @MainActor static func render() {
        let beats = cycle()
        var frames: [CGImage] = []
        for beat in beats {
            let small = MenuIcon.draw(beat.frame), large = MenuIcon.draw(beat.frame, side: 88)
            frames.append(bitmap(720, 250, scale: 1) { ctx in
                for (i, dark) in [false, true].enumerated() {
                    let x0 = CGFloat(i) * 360, ink = NSColor(white: dark ? 1 : 0, alpha: 0.85)
                    NSColor(white: dark ? 0.17 : 0.925, alpha: 1).set()
                    NSRect(x: x0, y: 0, width: 360, height: 250).fill()
                    ctx.draw(menuBar(small, dark: dark), in: CGRect(x: x0, y: 202, width: 360, height: 48))
                    tinted(large, ink).draw(in: NSRect(x: x0 + 136, y: 84, width: 88, height: 88))
                    let caption = NSAttributedString(string: beat.caption, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: ink])
                    caption.draw(at: NSPoint(x: x0 + 180 - caption.size().width / 2, y: 50))
                    let sub = NSAttributedString(string: dark ? "Dark menu bar" : "Light menu bar", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: ink.withAlphaComponent(0.5)])
                    sub.draw(at: NSPoint(x: x0 + 180 - sub.size().width / 2, y: 30))
                }
            })
        }
        for path in ["assets/menubar-animation.gif", "docs/assets/menubar-animation.gif"] {
            let url = root.appendingPathComponent(path)
            let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for (frame, beat) in zip(frames, beats) {
                CGImageDestinationAddImage(dest, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: beat.delay, kCGImagePropertyGIFUnclampedDelayTime: beat.delay]] as CFDictionary)
            }
            precondition(CGImageDestinationFinalize(dest), "couldn't write \(url.path)")
            print("wrote \(path): \(frames.count) frames, \(String(format: "%.1f", beats.map(\.delay).reduce(0, +))) s")
        }
    }
}
