// Draws the Installer window background (620×418 pt, drawn @2x) in the SleepLess night→sunrise palette: the app icon
// over a sunrise glow in the bottom-left corner, behind Installer's step list; everything else is clear, so the panes
// read as usual. One file per appearance — the step list's text is dark on light and light on dark, so is ours.
// Used by make-pkg.sh:  make-pkg-background <icon.png> <out-dir>  →  <out-dir>/background.png, <out-dir>/background-dark.png
import AppKit

let icon = NSImage(contentsOfFile: CommandLine.arguments[1])!, outDir = CommandLine.arguments[2]
let size = NSSize(width: 620, height: 418)
let centreX: CGFloat = 96   // the middle of Installer's step list

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let cream = hex(0xFFD9A8), night = hex(0x1E1B4B)

func rounded(_ pointSize: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: pointSize, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: pointSize) } ?? base
}

func text(_ string: String, _ font: NSFont, _ color: NSColor, centreX: CGFloat, y: CGFloat) {
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    attributed.draw(at: NSPoint(x: centreX - attributed.size().width / 2, y: y))
}

func draw(dark: Bool) {
    // The sunrise glow, low in the corner: warm on both appearances, deeper on dark.
    let glow = NSPoint(x: centreX, y: 92)
    NSGradient(colorsAndLocations: (hex(0xFFB35A, dark ? 0.42 : 0.30), 0), (hex(0xE0785E, dark ? 0.18 : 0.10), 0.55), (hex(0xE0785E, 0), 1))!
        .draw(fromCenter: glow, radius: 0, toCenter: glow, radius: 175, options: [])
    // A thin horizon under the icon, and — on dark — a few stars above it.
    let horizon = NSBezierPath()
    horizon.move(to: NSPoint(x: 22, y: 70))
    horizon.line(to: NSPoint(x: 170, y: 70))
    horizon.lineWidth = 1.5
    horizon.lineCapStyle = .round
    (dark ? cream : hex(0xD9795C)).withAlphaComponent(0.7).setStroke()
    horizon.stroke()
    if dark {
        for (x, y, r) in [(30.0, 196.0, 1.1), (66, 214, 0.8), (150, 206, 1.0), (176, 180, 0.7), (118, 222, 0.6)] as [(CGFloat, CGFloat, CGFloat)] {
            hex(0xFFFFFF, 0.75).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)).fill()
        }
    }
    // The app icon, sitting on the horizon, with a soft shadow.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.5 : 0.25)
    shadow.shadowBlurRadius = 10
    shadow.shadowOffset = NSSize(width: 0, height: -4)
    shadow.set()
    icon.draw(in: NSRect(x: centreX - 54, y: 74, width: 108, height: 108), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    text("SleepLess", rounded(17, .semibold), dark ? cream : night, centreX: centreX, y: 42)
    text("Weta Technologies Limited", rounded(11, .medium), (dark ? cream : night).withAlphaComponent(0.7), centreX: centreX, y: 26)
}

for dark in [false, true] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size   // points: the PNG carries 144 dpi, and Installer scales it to the window anyway
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(dark: dark)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(dark ? "background-dark.png" : "background.png"))
}
