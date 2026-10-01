// Draws the PowerLens app icon (a horizontal bolt inside a ring on a dark rounded square)
// and writes an .iconset directory with every size macOS expects.
// The glyph is drawn here from plain paths: SF Symbols may not be used in app icons.
//
// Usage: make_icon <output.iconset> [preview.png]
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make_icon <output.iconset> [preview.png]\n".utf8))
    exit(2)
}

/// Renders the icon at `pixels` × `pixels`. All geometry is defined on a 1024 grid.
func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    // Background: macOS icon grid (824 pt body, 100 pt margin), dark vertical gradient.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.23, blue: 0.29, alpha: 1),
               ending: NSColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 1))!
        .draw(in: shape, angle: -90)

    // Ring.
    let center = NSPoint(x: 512, y: 512)
    let radius: CGFloat = 268
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    ring.lineWidth = 44
    NSColor.white.withAlphaComponent(0.92).setStroke()
    ring.stroke()

    // Horizontal bolt: a classic bolt outline on a unit square, rotated a quarter turn.
    let outline: [(CGFloat, CGFloat)] = [
        (0.60, 0.00), (0.16, 0.58), (0.47, 0.58), (0.38, 1.00), (0.84, 0.40), (0.53, 0.40),
    ]
    let size: CGFloat = 420
    let bolt = NSBezierPath()
    for (i, p) in outline.enumerated() {
        // Unit (x, y) -> rotated so the bolt points left to right, centred in the ring.
        let x = center.x + (p.1 - 0.5) * size
        let y = center.y + (p.0 - 0.5) * size
        i == 0 ? bolt.move(to: NSPoint(x: x, y: y)) : bolt.line(to: NSPoint(x: x, y: y))
    }
    bolt.close()
    bolt.lineJoinStyle = .round
    NSGradient(starting: NSColor(srgbRed: 1.00, green: 0.84, blue: 0.29, alpha: 1),
               ending: NSColor(srgbRed: 1.00, green: 0.60, blue: 0.11, alpha: 1))!
        .draw(in: bolt, angle: -90)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = render(pixels: points * factor).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
if args.count >= 3 {
    try render(pixels: 256).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
}
