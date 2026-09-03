import AppKit

// Permissions for Mac icon: deep violet tile, a white card listing three permissions, each with a
// coloured dot (red, orange, green) and a switch. Reads as "the list" at every size.
func draw(_ s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.06
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.52, green: 0.30, blue: 0.78, alpha: 1),
                        NSColor(calibratedRed: 0.24, green: 0.14, blue: 0.46, alpha: 1)])!.draw(in: tile, angle: -70)
    let card = NSRect(x: s * 0.17, y: s * 0.19, width: s * 0.66, height: s * 0.62)
    NSColor.black.withAlphaComponent(0.18).setFill()
    NSBezierPath(roundedRect: card.offsetBy(dx: 0, dy: -s * 0.02), xRadius: s * 0.07, yRadius: s * 0.07).fill()
    NSColor.white.withAlphaComponent(0.97).setFill()
    NSBezierPath(roundedRect: card, xRadius: s * 0.07, yRadius: s * 0.07).fill()
    let dots = [NSColor(calibratedRed: 0.93, green: 0.27, blue: 0.27, alpha: 1), NSColor(calibratedRed: 0.98, green: 0.62, blue: 0.16, alpha: 1), NSColor(calibratedRed: 0.22, green: 0.72, blue: 0.42, alpha: 1)]
    let on = [true, true, false]
    for i in 0..<3 {
        let y = card.maxY - s * 0.13 - CGFloat(i) * s * 0.18
        dots[i].setFill()
        NSBezierPath(ovalIn: NSRect(x: card.minX + s * 0.07, y: y - s * 0.045, width: s * 0.09, height: s * 0.09)).fill()
        NSColor(calibratedWhite: 0.82, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: card.minX + s * 0.21, y: y - s * 0.02, width: s * 0.17, height: s * 0.04), xRadius: s * 0.02, yRadius: s * 0.02).fill()
        // switch
        let sw = NSRect(x: card.maxX - s * 0.22, y: y - s * 0.05, width: s * 0.15, height: s * 0.10)
        (on[i] ? NSColor(calibratedRed: 0.52, green: 0.30, blue: 0.78, alpha: 1) : NSColor(calibratedWhite: 0.80, alpha: 1)).setFill()
        NSBezierPath(roundedRect: sw, xRadius: s * 0.05, yRadius: s * 0.05).fill()
        NSColor.white.setFill()
        let knob = s * 0.08
        NSBezierPath(ovalIn: NSRect(x: on[i] ? sw.maxX - knob - s * 0.01 : sw.minX + s * 0.01, y: sw.midY - knob / 2, width: knob, height: knob)).fill()
    }
    img.unlockFocus()
    return img
}

let out = "icon/PermsMac.iconset"
try? FileManager.default.removeItem(atPath: out)
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),
                   ("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let img = draw(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("iconset written")
