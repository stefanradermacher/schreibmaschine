// Copyright 2026 Stefan Radermacher
//
// NOT covered by the Apache License 2.0 that applies to the rest of Schreibmaschine.
// This file draws the app icon and the document icon, which are marks of
// Stefan Radermacher and are reserved. See TRADEMARKS.md.

import AppKit

// Draws the Schreibmaschine app icon into the asset catalog and the document icon into Resources.
// Usage (from the project folder): swift scripts/make_icon.swift
// All drawing is done on a 1024 × 1024 canvas and scaled for the smaller sizes.

// MARK: helpers
func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func rr(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }
var ctx: CGContext { NSGraphicsContext.current!.cgContext }
/// Output size relative to 1024; shadows are not affected by the scaled drawing, so they scale by hand.
var outputScale: CGFloat = 1
/// Additional scale of the machine inside the icon; shadows follow it as well.
var drawingScale: CGFloat = 1
func shadow(_ blur: CGFloat, _ dy: CGFloat, _ alpha: CGFloat) {
    let s = outputScale * drawingScale
    ctx.setShadow(offset: CGSize(width: 0, height: dy * s), blur: blur * s,
                  color: NSColor.black.withAlphaComponent(alpha).cgColor)
}
func noShadow() { ctx.setShadow(offset: .zero, blur: 0, color: nil) }

// MARK: colours

let skyTop = c(0xA9C8EE), skyBottom = c(0x5E8CCB)          // steel blue background
let body = c(0x3B3F48), bodyDark = c(0x1C1E23)             // black lacquer of the machine
let well = c(0x0E0F12)                                     // keyboard well and type basket
let cream = c(0xF6ECCB), creamDark = c(0xE2D2A0)           // key faces
let ink = c(0x2B2F3A, 0.78)                                // typed text
let cursorColor = c(0xE8702E)                              // insertion point
let chrome = NSGradient(colors: [c(0xF6F6F8), c(0xA8A8B0), c(0xE4E4EA), c(0x74747C)],
                        atLocations: [0, 0.35, 0.6, 1], colorSpace: .sRGB)!

// MARK: parts

/// Squircle background on the macOS icon grid, steel blue.
func background() {
    let path = rr(NSRect(x: 100, y: 100, width: 824, height: 824), 185)
    NSGradient(starting: skyTop, ending: skyBottom)!.draw(in: path, angle: -90)
    ctx.saveGState(); path.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.16), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: 100, y: 600, width: 824, height: 324), angle: -90)
    ctx.restoreGState()
}

/// Typed lines: bars of different lengths at equal distances.
func typedLines(in r: NSRect, widths: [CGFloat], height: CGFloat, gap: CGFloat) {
    ink.setFill()
    for (i, w) in widths.enumerated() {
        rr(NSRect(x: r.minX, y: r.maxY - CGFloat(i) * gap - height, width: r.width * w, height: height), height / 2).fill()
    }
}

/// A key seen slightly from above: stem, chrome cylinder, cream face.
func key(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
    let h = w * 0.36, side = w * 0.22
    c(0x000000, 0.55).setFill()
    NSBezierPath(rect: NSRect(x: x - w * 0.09, y: y - side - w * 0.55, width: w * 0.18, height: w * 0.55)).fill()
    let cylinder = NSBezierPath(ovalIn: NSRect(x: x - w / 2, y: y - side - h / 2, width: w, height: h))
    cylinder.append(NSBezierPath(rect: NSRect(x: x - w / 2, y: y - side, width: w, height: side)))
    shadow(5, -3, 0.4); chrome.draw(in: cylinder, angle: 0); noShadow()
    chrome.draw(in: NSBezierPath(ovalIn: NSRect(x: x - w / 2, y: y - h / 2, width: w, height: h)), angle: 180)
    let inset = w * 0.08
    let face = NSBezierPath(ovalIn: NSRect(x: x - w / 2 + inset, y: y - h / 2 + inset * 0.6, width: w - 2 * inset, height: h - 1.2 * inset))
    NSGradient(starting: cream, ending: cream.blended(withFraction: 0.25, of: creamDark)!)!.draw(in: face, angle: -90)
}

/// Knob of the platen with grooves.
func knob(_ r: NSRect) {
    let path = rr(r, 12)
    shadow(8, -4, 0.4)
    NSGradient(colors: [body.blended(withFraction: 0.3, of: .white)!, bodyDark, body, bodyDark.blended(withFraction: 0.4, of: .black)!],
               atLocations: [0, 0.35, 0.65, 1], colorSpace: .sRGB)!.draw(in: path, angle: -90)
    noShadow()
    ctx.saveGState(); path.addClip()
    c(0x000000, 0.28).setFill()
    var x = r.minX + 6
    while x < r.maxX - 4 { NSBezierPath(rect: NSRect(x: x, y: r.minY, width: 4, height: r.height)).fill(); x += 11 }
    ctx.restoreGState()
}

/// The typewriter from the front, drawn on the full canvas and scaled into the icon by the caller.
func typewriter() {
    // paper behind the platen
    shadow(18, -4, 0.25)
    NSGradient(starting: c(0xFFFDF6), ending: c(0xF7EFD9))!.draw(in: NSBezierPath(rect: NSRect(x: 318, y: 600, width: 388, height: 268)), angle: -90)
    noShadow()
    typedLines(in: NSRect(x: 360, y: 680, width: 304, height: 150), widths: [0.62, 0.92, 0.8, 0.4], height: 20, gap: 38)
    cursorColor.setFill()
    NSBezierPath(rect: NSRect(x: 360 + 304 * 0.4 + 10, y: 830 - 3 * 38 - 20 - 6, width: 9, height: 32)).fill()

    // upper body with the opening for the type basket
    let upper = rr(NSRect(x: 214, y: 400, width: 596, height: 196), 16)
    shadow(24, -8, 0.35)
    NSGradient(starting: body, ending: bodyDark)!.draw(in: upper, angle: -90)
    noShadow()
    let recess = NSBezierPath()
    recess.move(to: NSPoint(x: 352, y: 596))
    recess.line(to: NSPoint(x: 672, y: 596))
    recess.curve(to: NSPoint(x: 512, y: 430), controlPoint1: NSPoint(x: 662, y: 480), controlPoint2: NSPoint(x: 600, y: 430))
    recess.curve(to: NSPoint(x: 352, y: 596), controlPoint1: NSPoint(x: 424, y: 430), controlPoint2: NSPoint(x: 362, y: 480))
    recess.close()
    well.setFill(); recess.fill()
    ctx.saveGState(); recess.addClip()
    let hub = NSPoint(x: 512, y: 572)
    c(0xC8CCD4, 0.85).setStroke()
    for i in 0...40 {
        let angle = CGFloat.pi * (1.08 + 0.84 * CGFloat(i) / 40)
        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: hub.x + cos(angle) * 70, y: hub.y + sin(angle) * 70))
        bar.line(to: NSPoint(x: hub.x + cos(angle) * 150, y: hub.y + sin(angle) * 150))
        bar.lineWidth = 3
        bar.stroke()
    }
    ctx.restoreGState()
    body.blended(withFraction: 0.45, of: .white)!.setStroke()
    recess.lineWidth = 5; recess.stroke()
    chrome.draw(in: rr(NSRect(x: 492, y: 560, width: 40, height: 44), 4), angle: 0)

    // ribbon spools
    for x in [CGFloat(282), 742] {
        let side = NSBezierPath(rect: NSRect(x: x - 62, y: 540, width: 124, height: 30))
        side.appendOval(in: NSRect(x: x - 62, y: 522, width: 124, height: 36))
        shadow(6, -3, 0.35); chrome.draw(in: side, angle: 0); noShadow()
        NSGradient(colors: [c(0xFFFFFF), c(0xB4B4BC), c(0xEDEDF2), c(0x9A9AA2)], atLocations: [0, 0.4, 0.7, 1], colorSpace: .sRGB)!
            .draw(in: NSBezierPath(ovalIn: NSRect(x: x - 62, y: 552, width: 124, height: 38)), angle: 30)
    }

    // platen and knobs
    shadow(12, -5, 0.45)
    NSGradient(colors: [c(0x4A4A50), c(0x121214), c(0x2C2C30), c(0x060607)], atLocations: [0, 0.45, 0.8, 1], colorSpace: .sRGB)!
        .draw(in: rr(NSRect(x: 206, y: 596, width: 612, height: 46), 23), angle: -90)
    noShadow()
    c(0xFFFFFF, 0.2).setFill(); rr(NSRect(x: 230, y: 628, width: 564, height: 7), 3.5).fill()
    knob(NSRect(x: 150, y: 578, width: 64, height: 82))
    knob(NSRect(x: 810, y: 578, width: 64, height: 82))

    // keyboard: straight sides, wider at the bottom, dark well inside
    let keyboard = NSBezierPath()
    keyboard.move(to: NSPoint(x: 226, y: 420)); keyboard.line(to: NSPoint(x: 798, y: 420))
    keyboard.line(to: NSPoint(x: 862, y: 160)); keyboard.line(to: NSPoint(x: 162, y: 160)); keyboard.close()
    shadow(20, -6, 0.3)
    NSGradient(starting: body.blended(withFraction: 0.15, of: .white)!, ending: bodyDark)!.draw(in: keyboard, angle: -90)
    noShadow()
    let wellPath = NSBezierPath()
    wellPath.move(to: NSPoint(x: 250, y: 404)); wellPath.line(to: NSPoint(x: 774, y: 404))
    wellPath.line(to: NSPoint(x: 830, y: 184)); wellPath.line(to: NSPoint(x: 194, y: 184)); wellPath.close()
    NSGradient(starting: well, ending: well.blended(withFraction: 0.3, of: .black)!)!.draw(in: wellPath, angle: -90)

    let rows: [(y: CGFloat, count: Int, spacing: CGFloat, w: CGFloat, offset: CGFloat)] = [
        (378, 9, 58, 46, 0), (318, 9, 62, 50, 16), (256, 8, 66, 54, 0)]
    for row in rows {
        let width = CGFloat(row.count - 1) * row.spacing
        for i in 0..<row.count { key(512 - width / 2 + row.offset + CGFloat(i) * row.spacing, row.y, row.w) }
    }
    shadow(4, -3, 0.4)
    NSGradient(starting: cream, ending: creamDark)!.draw(in: rr(NSRect(x: 340, y: 198, width: 344, height: 22), 11), angle: -90)
    noShadow()
    chrome.draw(in: rr(NSRect(x: 340, y: 192, width: 344, height: 10), 5), angle: 0)

    // base with a light edge
    shadow(16, -6, 0.35)
    NSGradient(starting: body, ending: bodyDark.blended(withFraction: 0.35, of: .black)!)!
        .draw(in: rr(NSRect(x: 136, y: 104, width: 752, height: 64), 10), angle: -90)
    noShadow()
    body.blended(withFraction: 0.55, of: .white)!.setFill()
    rr(NSRect(x: 146, y: 158, width: 732, height: 6), 3).fill()
}

// MARK: icons

/// The app icon: the typewriter standing on the steel blue squircle, with room below.
func drawIcon() {
    background()
    // soft shadow on the ground
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40 * outputScale, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    c(0x000000, 0.25).setFill()
    NSBezierPath(ovalIn: NSRect(x: 200, y: 168, width: 624, height: 40)).fill()
    ctx.restoreGState()

    ctx.saveGState()
    drawingScale = 0.84
    ctx.translateBy(x: 512, y: 196)
    ctx.scaleBy(x: drawingScale, y: drawingScale)
    ctx.translateBy(x: -512, y: -104)
    typewriter()
    ctx.restoreGState()
    drawingScale = 1
}

/// The document icon: a page with a folded steel blue corner, filled with typed lines and the
/// orange insertion point, as the page of Leser's document icon is filled with text.
func drawDocumentIcon() {
    let r = NSRect(x: 142, y: 40, width: 740, height: 950)
    let fold = r.width * 0.27
    let page = NSBezierPath()
    page.move(to: NSPoint(x: r.minX, y: r.minY)); page.line(to: NSPoint(x: r.maxX, y: r.minY))
    page.line(to: NSPoint(x: r.maxX, y: r.maxY - fold)); page.line(to: NSPoint(x: r.maxX - fold, y: r.maxY))
    page.line(to: NSPoint(x: r.minX, y: r.maxY)); page.close()
    shadow(34, -14, 0.34); NSColor.white.setFill(); page.fill(); noShadow()

    let margin = r.width * 0.12
    // The text starts at the top margin, as on Leser's page; the lines beside the folded corner
    // stay short of it.
    let text = NSRect(x: r.minX + margin, y: r.minY + margin * 1.2, width: r.width - 2 * margin, height: r.height - margin * 2.2)
    let widths: [CGFloat] = [0.5, 0.72, 0.95, 0.88, 0.92, 0.7, 0.9, 0.84, 0.93, 0.8, 0.35]
    typedLines(in: text, widths: widths, height: 34, gap: 72)
    cursorColor.setFill()
    let last = CGFloat(widths.count - 1)
    NSBezierPath(rect: NSRect(x: text.minX + text.width * 0.35 + 16, y: text.maxY - last * 72 - 34 - 10, width: 16, height: 54)).fill()

    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: r.maxX - fold, y: r.maxY)); corner.line(to: NSPoint(x: r.maxX - fold, y: r.maxY - fold))
    corner.line(to: NSPoint(x: r.maxX, y: r.maxY - fold)); corner.close()
    shadow(12, -5, 0.22); skyBottom.setFill(); corner.fill(); noShadow()
}

// MARK: output

let out = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func png(_ px: Int, _ draw: () -> Void = drawIcon) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    outputScale = CGFloat(px) / 1024
    ctx.scaleBy(x: outputScale, y: outputScale)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try! png(size * scale).write(to: out.appendingPathComponent(name))
        images.append("""
            { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(size)x\(size)" }
        """)
    }
}

// Document icon as .icns next to the app icon
let docSet = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DocumentIcon.iconset")
try? FileManager.default.removeItem(at: docSet)
try! FileManager.default.createDirectory(at: docSet, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! png(size, drawDocumentIcon).write(to: docSet.appendingPathComponent("icon_\(size)x\(size).png"))
    try! png(size * 2, drawDocumentIcon).write(to: docSet.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", docSet.path, "-o", "Resources/TextDocument.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: docSet)

let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try! contents.write(to: out.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
let catalog = URL(fileURLWithPath: "Resources/Assets.xcassets/Contents.json")
if !FileManager.default.fileExists(atPath: catalog.path) {
    try! "{\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n".write(to: catalog, atomically: true, encoding: .utf8)
}
