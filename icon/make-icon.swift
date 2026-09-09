import AppKit

// Plain for Mac. The same ochre as Plain for Windows, and the same idea in one picture: a page whose first lines
// are solid and whose later lines are still there but faded. What Plain draws, and what it keeps without drawing.
func draw(_ s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    let inset = s * 0.06
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset),
                            xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.75, green: 0.54, blue: 0.17, alpha: 1),
                        NSColor(calibratedRed: 0.56, green: 0.38, blue: 0.08, alpha: 1)])!.draw(in: tile, angle: -70)

    let pageWidth = s * 0.52, pageHeight = s * 0.62
    let page = NSBezierPath(roundedRect: NSRect(x: (s - pageWidth) / 2, y: (s - pageHeight) / 2,
                                                width: pageWidth, height: pageHeight),
                            xRadius: s * 0.035, yRadius: s * 0.035)
    NSColor.white.withAlphaComponent(0.97).setFill()
    page.fill()

    // The first lines solid, the rest faded but present. Nothing is missing from the page; some of it is simply
    // not drawn in full, which is exactly what the program does with a file.
    let left = (s - pageWidth) / 2 + pageWidth * 0.14
    let lineWidth = pageWidth * 0.72
    let top = (s - pageHeight) / 2 + pageHeight * 0.78
    let gap = pageHeight * 0.115
    let thickness = max(1, s * 0.028)
    let ink = NSColor(calibratedRed: 0.20, green: 0.14, blue: 0.04, alpha: 1)

    for i in 0..<6 {
        let y = top - CGFloat(i) * gap
        let width = (i == 2 || i == 5) ? lineWidth * 0.55 : lineWidth
        ink.withAlphaComponent(i < 3 ? 0.92 : 0.22).setFill()
        NSBezierPath(roundedRect: NSRect(x: left, y: y, width: width, height: thickness),
                     xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }

    img.unlockFocus()
    return img
}

let out = "icon/Plain.iconset"
try? FileManager.default.removeItem(atPath: out)
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                   ("512x512", 512), ("512x512@2x", 1024)] {
    let img = draw(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("iconset written")
