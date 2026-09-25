// Renders assets/banner.png (1280x640, also the GitHub social preview): `swift assets/make-banner.swift`
// Needs assets/icon-1024.png from make-icon.swift.
import AppKit

let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let W = 1280, H = 640

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

func rounded(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

func text(_ string: String, _ font: NSFont, _ color: CGColor, at point: CGPoint, tracking: CGFloat = 0) {
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: tracking]).draw(at: point)
}

let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

// Night sky with the sunrise glow along the bottom edge — the icon's palette, stretched wide.
ctx.drawLinearGradient(gradient([(0, srgb(0x0C0D2A)), (0.55, srgb(0x1E1A52)), (1, srgb(0x3A2668))]),
                       start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
ctx.drawRadialGradient(gradient([(0, srgb(0xFFA85A, 0.55)), (0.5, srgb(0xE2624F, 0.22)), (1, srgb(0xE2624F, 0))]),
                       startCenter: CGPoint(x: 640, y: -160), startRadius: 0, endCenter: CGPoint(x: 640, y: -160), endRadius: 760, options: [])
ctx.setFillColor(srgb(0xFFFFFF, 0.75))
for (x, y, r) in [(90, 560, 3), (210, 470, 2), (330, 600, 2.5), (760, 590, 2), (980, 540, 3), (1120, 470, 2), (1220, 580, 2.5), (560, 520, 1.5), (1050, 330, 1.5)] as [(CGFloat, CGFloat, CGFloat)] {
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}
// Horizon line along the very bottom.
ctx.setFillColor(srgb(0xFFD9A8, 0.9))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: 6))

// Icon (already has its own shadow), left of centre.
let icon = NSImage(contentsOf: assets.appendingPathComponent("icon-1024.png"))!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
ctx.draw(icon, in: CGRect(x: 96, y: 108, width: 424, height: 424))

// Wordmark + tagline.
text("SleepLess", rounded(132, weight: .bold), srgb(0xFFFFFF), at: CGPoint(x: 536, y: 318), tracking: -3)
text("Keep your Mac awake — lid open or closed.", rounded(36, weight: .medium), srgb(0xFFD9A8), at: CGPoint(x: 544, y: 254))
text("Free menu-bar app for macOS · by CyborgFingers", rounded(25, weight: .regular), srgb(0xB4B0E0), at: CGPoint(x: 546, y: 206))

let out = assets.appendingPathComponent("banner.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest), "couldn't write banner")
print("Wrote banner.png")
