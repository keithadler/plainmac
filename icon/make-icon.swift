import AppKit
// Plain for Mac icon. Change the shapes and the gradient; keep the rounded tile and the 10 sizes.
func draw(_ s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s)); img.lockFocus()
    let inset = s * 0.06
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.50, blue: 0.48, alpha: 1), NSColor(calibratedRed: 0.06, green: 0.20, blue: 0.26, alpha: 1)])!.draw(in: tile, angle: -70)
    // eye outline
    let eye = NSBezierPath(); eye.move(to: NSPoint(x: s * 0.14, y: s * 0.50))
    eye.curve(to: NSPoint(x: s * 0.86, y: s * 0.50), controlPoint1: NSPoint(x: s * 0.34, y: s * 0.86), controlPoint2: NSPoint(x: s * 0.66, y: s * 0.86))
    eye.curve(to: NSPoint(x: s * 0.14, y: s * 0.50), controlPoint1: NSPoint(x: s * 0.66, y: s * 0.14), controlPoint2: NSPoint(x: s * 0.34, y: s * 0.14))
    NSColor.white.withAlphaComponent(0.96).setFill(); eye.fill()
    // iris and pupil
    NSColor(calibratedRed: 0.06, green: 0.20, blue: 0.26, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.36, y: s * 0.36, width: s * 0.28, height: s * 0.28)).fill()
    NSColor(calibratedRed: 0.16, green: 0.50, blue: 0.48, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.40, y: s * 0.40, width: s * 0.20, height: s * 0.20)).fill()
    NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: s * 0.50, y: s * 0.52, width: s * 0.06, height: s * 0.06)).fill()
    // the dot
    NSColor(calibratedRed: 0.98, green: 0.60, blue: 0.16, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.70, y: s * 0.66, width: s * 0.12, height: s * 0.12)).fill()
    img.unlockFocus(); return img
}
let out = "icon/Plain.iconset"
try? FileManager.default.removeItem(atPath: out); try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let img = draw(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px)); NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("iconset written")
