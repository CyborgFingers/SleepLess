// Draws the DMG window background (640×400 pt, @1x + @2x) in the SleepLess night→sunrise palette.
// Used by make-dmg.sh:  make-dmg-background <version> <out-dir>  →  <out-dir>/bg.png, <out-dir>/bg@2x.png
// Finder draws icon labels black in Light mode and white in Dark mode, so the band the labels sit on is a
// mid-tone (≈5:1 against white, ≈4:1 against black) — both stay readable.
import AppKit

let version = CommandLine.arguments[1], outDir = CommandLine.arguments[2]
let size = NSSize(width: 640, height: 400)
let appX: CGFloat = 160, appsX: CGFloat = 480, iconY: CGFloat = 180   // Finder icon centres, from the top

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let cream = hex(0xFFD9A8)

func rounded(_ pointSize: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: pointSize, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: pointSize) } ?? base
}

func text(_ string: String, _ font: NSFont, _ color: NSColor, centreX: CGFloat, top: CGFloat) {
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    let w = attributed.size()
    attributed.draw(at: NSPoint(x: centreX - w.width / 2, y: size.height - top - w.height))
}

func draw() {
    // Sky: night at the top, a dusky mid-tone where the labels sit, warm glow down to the horizon.
    NSGradient(colorsAndLocations:
        (hex(0x0E0F2E), 0.0), (hex(0x241D58), 0.42), (hex(0x86607F), 0.62), (hex(0xD9795C), 0.80), (hex(0xF0A36A), 0.845)
    )!.draw(in: NSRect(x: 0, y: size.height * (1 - 0.845), width: size.width, height: size.height * 0.845), angle: -90)
    // Below the horizon: calm dark water.
    NSGradient(starting: hex(0x2A1F4A), ending: hex(0x141130))!
        .draw(in: NSRect(x: 0, y: 0, width: size.width, height: size.height * (1 - 0.845)), angle: -90)
    // Sun glow sitting on the horizon.
    let horizon = size.height * (1 - 0.845)
    NSGradient(starting: hex(0xFFD08A, 0.55), ending: hex(0xFFB35A, 0))!
        .draw(fromCenter: NSPoint(x: size.width / 2, y: horizon), radius: 0, toCenter: NSPoint(x: size.width / 2, y: horizon), radius: 150, options: [])
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 36, y: horizon))
    line.line(to: NSPoint(x: size.width - 36, y: horizon))
    line.lineWidth = 2
    line.lineCapStyle = .round
    cream.withAlphaComponent(0.9).setStroke()
    line.stroke()

    // Stars in the night part.
    for (x, y, r) in [(40.0, 30.0, 1.2), (96, 92, 0.9), (212, 24, 1.1), (286, 104, 0.8), (390, 38, 1.2), (452, 110, 0.9),
                      (548, 26, 1.1), (604, 84, 0.9), (148, 140, 0.7), (520, 150, 0.7), (350, 128, 0.6)] as [(CGFloat, CGFloat, CGFloat)] {
        hex(0xFFFFFF, 0.8).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - r, y: size.height - y - r, width: 2 * r, height: 2 * r)).fill()
    }

    text("Drag SleepLess into Applications", rounded(20, .semibold), cream, centreX: size.width / 2, top: 50)

    // Arrow from the app to Applications.
    let y = size.height - iconY
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: appX + 84, y: y))
    arrow.line(to: NSPoint(x: appsX - 88, y: y))
    arrow.move(to: NSPoint(x: appsX - 102, y: y + 12))
    arrow.line(to: NSPoint(x: appsX - 88, y: y))
    arrow.line(to: NSPoint(x: appsX - 102, y: y - 12))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    let glow = NSShadow()
    glow.shadowColor = hex(0xFFB35A, 0.6)
    glow.shadowBlurRadius = 8
    NSGraphicsContext.saveGraphicsState()
    glow.set()
    cream.setStroke()
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()

    text("SleepLess \(version)  ·  by CyborgFingers  ·  github.com/CyborgFingers/SleepLess",
         rounded(11, .medium), cream.withAlphaComponent(0.75), centreX: size.width / 2, top: 368)
}

for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size   // points, so @2x carries 144 dpi for tiffutil -cathidpicheck
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "bg.png" : "bg@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
