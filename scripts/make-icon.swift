// Renders Resources/AppIcon.icns: a rounded tile with a preview bubble over a dock.
import AppKit
let out = CommandLine.arguments[1]
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let tile = NSRect(x: s*0.1, y: s*0.1, width: s*0.8, height: s*0.8)
    NSGradient(colors: [NSColor(red: 0.18, green: 0.52, blue: 0.98, alpha: 1), NSColor(red: 0.45, green: 0.25, blue: 0.9, alpha: 1)])!
        .draw(in: NSBezierPath(roundedRect: tile, xRadius: s*0.18, yRadius: s*0.18), angle: -70)
    // dock
    NSColor(white: 1, alpha: 0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: s*0.2, y: s*0.18, width: s*0.6, height: s*0.1), xRadius: s*0.03, yRadius: s*0.03).fill()
    // bubble + pointer
    NSColor(white: 0.1, alpha: 0.85).setFill()
    let bubble = NSBezierPath(roundedRect: NSRect(x: s*0.2, y: s*0.38, width: s*0.6, height: s*0.36), xRadius: s*0.05, yRadius: s*0.05)
    bubble.move(to: NSPoint(x: s*0.45, y: s*0.38)); bubble.line(to: NSPoint(x: s*0.5, y: s*0.32)); bubble.line(to: NSPoint(x: s*0.55, y: s*0.38))
    bubble.fill()
    // thumbnails
    for (i, a) in [0.95, 0.55].enumerated() {
        NSColor(white: 1, alpha: a).setFill()
        NSBezierPath(roundedRect: NSRect(x: s*(0.25 + CGFloat(i)*0.26), y: s*0.46, width: s*0.22, height: s*0.2), xRadius: s*0.02, yRadius: s*0.02).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let set = out + ".iconset"
try? FileManager.default.removeItem(atPath: set)
try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
