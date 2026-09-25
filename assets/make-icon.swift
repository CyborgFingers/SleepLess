// Renders the SleepLess app icon: `swift assets/make-icon.swift`
// Writes assets/icon-1024.png, assets/icon-512.png and assets/AppIcon.icns (via iconutil).
// Same glyph language as MenuIcon.swift: a rounded lid, a horizon line, a sun coming up with rays.
import AppKit

let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

func render(_ pixels: Int, _ draw: (CGContext, CGFloat) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx, CGFloat(pixels) / 1024)   // everything below is laid out on a 1024 canvas
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "couldn't write \(url.path)")
}

/// The icon on Apple's grid: 824 pt body centred on a 1024 canvas, soft shadow.
func drawIcon(_ ctx: CGContext, _ s: CGFloat) {
    ctx.scaleBy(x: s, y: s)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: srgb(0x000000, 0.32))
    ctx.addPath(shape); ctx.setFillColor(srgb(0x1B1A3F)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()

    // Sky: night at the top, sunrise at the horizon.
    let horizon = CGPoint(x: 512, y: body.minY + 236)
    ctx.drawLinearGradient(gradient([(0, 0x0E0F2E), (0.36, 0x2B2466), (0.6, 0x7A3C7E), (0.8, 0xE2624F), (1, 0xFFB35A)].map { ($0.0, srgb($0.1)) }),
                           start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: horizon.y), options: [.drawsAfterEndLocation])

    // Warm glow bleeding up from the sun.
    ctx.drawRadialGradient(gradient([(0, srgb(0xFFD27A, 0.55)), (0.45, srgb(0xFF9A5A, 0.22)), (1, srgb(0xFF8A5A, 0))]),
                           startCenter: horizon, startRadius: 0, endCenter: horizon, endRadius: 470, options: [])

    // Stars.
    ctx.setFillColor(srgb(0xFFFFFF, 0.85))
    for (x, y, r) in [(262, 786, 7), (392, 848, 4.5), (640, 812, 5.5), (760, 730, 4), (210, 640, 3.5), (738, 838, 3), (560, 870, 3)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    // Ground below the horizon, so the sun sits on something, with a faint reflection of the sun.
    ctx.saveGState()
    ctx.clip(to: CGRect(x: body.minX, y: body.minY, width: body.width, height: horizon.y - body.minY))
    ctx.drawLinearGradient(gradient([(0, srgb(0x3A2260)), (1, srgb(0x130E30))]),
                           start: CGPoint(x: 512, y: horizon.y), end: CGPoint(x: 512, y: body.minY), options: [])
    ctx.drawRadialGradient(gradient([(0, srgb(0xFFB35A, 0.35)), (1, srgb(0xFFB35A, 0))]),
                           startCenter: horizon, startRadius: 0, endCenter: horizon, endRadius: 260, options: [])
    ctx.restoreGState()

    // Sun: a half disc rising over the horizon, glowing.
    let sunRadius: CGFloat = 132
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46, color: srgb(0xFFC65A, 0.9))
    ctx.move(to: CGPoint(x: horizon.x - sunRadius, y: horizon.y))
    ctx.addArc(center: horizon, radius: sunRadius, startAngle: .pi, endAngle: 0, clockwise: true)
    ctx.closePath()
    ctx.setFillColor(srgb(0xFFE38A)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.move(to: CGPoint(x: horizon.x - sunRadius, y: horizon.y))
    ctx.addArc(center: horizon, radius: sunRadius, startAngle: .pi, endAngle: 0, clockwise: true)
    ctx.closePath(); ctx.clip()
    ctx.drawRadialGradient(gradient([(0, srgb(0xFFFBE6)), (0.55, srgb(0xFFE79A)), (1, srgb(0xFFC15A))]),
                           startCenter: CGPoint(x: horizon.x, y: horizon.y + 30), startRadius: 0,
                           endCenter: horizon, endRadius: sunRadius, options: [])
    ctx.restoreGState()

    // Horizon line and rays: the same geometry as the menu-bar glyph, in cream with a warm glow.
    ctx.setLineCap(.round)
    ctx.setLineWidth(max(58 * s, 1.2) / s)
    ctx.setStrokeColor(srgb(0xFFF4DA))
    ctx.setShadow(offset: .zero, blur: 18, color: srgb(0xFFB05A, 0.8))
    ctx.move(to: CGPoint(x: 236, y: horizon.y)); ctx.addLine(to: CGPoint(x: 788, y: horizon.y)); ctx.strokePath()
    let origin = CGPoint(x: horizon.x, y: horizon.y + 58)
    for degrees in [155.0, 122, 90, 58, 25] {
        let a = degrees * .pi / 180, inner: CGFloat = 200, outer: CGFloat = 318
        ctx.move(to: CGPoint(x: origin.x + cos(a) * inner, y: origin.y + sin(a) * inner))
        ctx.addLine(to: CGPoint(x: origin.x + cos(a) * outer, y: origin.y + sin(a) * outer))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Glass edge highlight.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
    ctx.setLineWidth(4); ctx.setStrokeColor(srgb(0xFFFFFF, 0.14)); ctx.strokePath()
    ctx.restoreGState()
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        writePNG(render(points * scale, drawIcon), iconset.appendingPathComponent(name))
    }
}
writePNG(render(1024, drawIcon), assets.appendingPathComponent("icon-1024.png"))
writePNG(render(512, drawIcon), assets.appendingPathComponent("icon-512.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
print("Wrote icon-1024.png, icon-512.png, AppIcon.icns")
