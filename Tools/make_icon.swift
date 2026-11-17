// Zeichnet das App-Icon (rotes Radar) als 1024×1024 PNG.
// Aufruf: swift Tools/make_icon.swift <ausgabe.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Hintergrund: abgerundetes Quadrat mit Verlauf
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bgPath = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.45).cgColor)
ctx.addPath(bgPath); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()
let cs = CGColorSpaceCreateDeviceRGB()
let bg = CGGradient(colorsSpace: cs, colors: [
    NSColor(red: 0.98, green: 0.22, blue: 0.27, alpha: 1).cgColor,
    NSColor(red: 0.62, green: 0.04, blue: 0.10, alpha: 1).cgColor,
    NSColor(red: 0.22, green: 0.01, blue: 0.04, alpha: 1).cgColor,
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

let c = CGPoint(x: size / 2, y: size / 2)
// Radar-Sweep
let sweepR: CGFloat = 330
for i in 0..<90 {
    let a0 = CGFloat(i) * .pi / 180 * 1.0 + .pi * 0.25
    let alpha = CGFloat(i) / 90 * 0.55
    ctx.move(to: c)
    ctx.addArc(center: c, radius: sweepR, startAngle: a0, endAngle: a0 + .pi / 180 * 1.2, clockwise: false)
    ctx.closePath()
    ctx.setFillColor(NSColor(white: 1, alpha: alpha * 0.6).cgColor)
    ctx.fillPath()
}
// Ringe
ctx.setLineWidth(14)
for r in [110, 220, 330] as [CGFloat] {
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.85).cgColor)
    ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}
// Sweep-Linie
ctx.setLineWidth(18); ctx.setLineCap(.round)
ctx.setStrokeColor(NSColor.white.cgColor)
let end = CGPoint(x: c.x + cos(.pi * 0.75) * sweepR, y: c.y + sin(.pi * 0.75) * sweepR)
ctx.move(to: c); ctx.addLine(to: end); ctx.strokePath()
// Blips
for (x, y, r) in [(0.30, 0.36, 30.0), (-0.18, 0.12, 22.0), (0.12, -0.27, 26.0), (-0.26, -0.20, 18.0)] as [(CGFloat, CGFloat, CGFloat)] {
    let p = CGPoint(x: c.x + x * size, y: c.y + y * size)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
}
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillEllipse(in: CGRect(x: c.x - 26, y: c.y - 26, width: 52, height: 52))
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Icon geschrieben: \(out)")
