// Copyright 2026 Stefan Radermacher
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// Creates the backgrounds of the document icons, one for each group of formats, in the colors
// of the app icon. macOS draws the page, the folded corner and the label below (UTTypeIcons in
// Info.plist); the background fills the upper part of the page, about 72 % of the square.
// Usage (from the project folder): swift scripts/make_document_icons.swift

import AppKit

func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let cursorOrange = c(0xE8702E)

/// What goes on a background, drawn into a square of side 1024 with the filled part from
/// y = fillBottom to the top.
enum Mark {
    case lines, braces, angles, gear, grid, plusMinus
}

struct Group {
    let name: String
    let top: NSColor, bottom: NSColor
    let mark: Mark
    let markColor: NSColor
}

let groups = [
    Group(name: "Text-fill", top: c(0x5E8CCB), bottom: c(0xA9C8EE), mark: .lines, markColor: .white),
    Group(name: "Code-fill", top: c(0x1C1E23), bottom: c(0x4A4F5A), mark: .braces, markColor: c(0xF6ECCB)),
    Group(name: "Markup-fill", top: c(0xC9561D), bottom: c(0xF2A066), mark: .angles, markColor: .white),
    Group(name: "Config-fill", top: c(0x74747C), bottom: c(0xC4C4CC), mark: .gear, markColor: .white),
    Group(name: "Data-fill", top: c(0xD9C68E), bottom: c(0xF6ECCB), mark: .grid, markColor: c(0x3B3F48)),
    Group(name: "Diff-fill", top: c(0x3F68A6), bottom: c(0x7FA4DA), mark: .plusMinus, markColor: .white),
]

let side: CGFloat = 1024
let fillBottom: CGFloat = 0.28 * side
var area: NSRect { NSRect(x: 0, y: fillBottom, width: side, height: side - fillBottom) }

func draw(_ group: Group) {
    NSGradient(starting: group.bottom, ending: group.top)!.draw(in: area, angle: 90)
    group.markColor.setFill()
    group.markColor.setStroke()
    let center = NSPoint(x: area.midX, y: area.midY)
    switch group.mark {
    case .lines:
        // Lines of typed text, the last one ending in the insertion point of the app icon.
        let rows: [[CGFloat]] = [[150, 90, 60], [70, 110], [190, 110, 100], [], [120, 200, 70], [130, 60]]
        var y = center.y + 150
        for row in rows {
            var x = center.x - 220
            for width in row {
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: 34), xRadius: 6, yRadius: 6).fill()
                x += width + 26
            }
            y -= row.isEmpty ? 30 : 62
        }
        cursorOrange.setFill()
        NSBezierPath(roundedRect: NSRect(x: center.x - 220 + 130 + 26 + 60 + 14, y: y + 62 - 14, width: 18, height: 62), xRadius: 4, yRadius: 4).fill()
    case .braces:
        text("{}", size: 360, color: group.markColor, at: center)
    case .angles:
        text("</>", size: 290, color: group.markColor, at: center)
    case .plusMinus:
        text("±", size: 400, color: group.markColor, at: center)
    case .gear:
        let path = NSBezierPath()
        let teeth = 8, outer: CGFloat = 230, inner: CGFloat = 178
        for index in 0..<(teeth * 4) {
            let angle = CGFloat(index) / CGFloat(teeth * 4) * 2 * .pi
            let radius = (index % 4 == 0 || index % 4 == 1) ? outer : inner
            let point = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.line(to: point)
        }
        path.close()
        path.appendOval(in: NSRect(x: center.x - 82, y: center.y - 82, width: 164, height: 164))
        path.windingRule = .evenOdd
        path.fill()
    case .grid:
        let cell = NSSize(width: 150, height: 92), columns = 3, rows = 4
        let origin = NSPoint(x: center.x - CGFloat(columns) * cell.width / 2, y: center.y - CGFloat(rows) * cell.height / 2)
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = NSRect(x: origin.x + CGFloat(column) * cell.width + 7, y: origin.y + CGFloat(row) * cell.height + 7,
                                  width: cell.width - 14, height: cell.height - 14)
                // The header row is solid, the others are outlined.
                if row == rows - 1 {
                    NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                } else {
                    let frame = NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 6, yRadius: 6)
                    frame.lineWidth = 10
                    frame.stroke()
                }
            }
        }
    }
}

func text(_ string: String, size: CGFloat, color: NSColor, at center: NSPoint) {
    let font = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    let bounds = attributed.boundingRect(with: .zero, options: [.usesDeviceMetrics])
    attributed.draw(at: NSPoint(x: center.x - bounds.midX, y: center.y - bounds.midY))
}

func image(_ group: Group, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(group)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let catalog = URL(fileURLWithPath: "Resources/Assets.xcassets")
let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for group in groups {
    let folder = catalog.appendingPathComponent(group.name + ".iconset")
    try? FileManager.default.removeItem(at: folder)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var entries: [String] = []
    for (points, scale) in sizes {
        let file = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! image(group, pixels: points * scale).write(to: folder.appendingPathComponent(file))
        entries.append("""
            {
              "filename" : "\(file)",
              "idiom" : "mac",
              "scale" : "\(scale)x",
              "size" : "\(points)x\(points)"
            }
        """)
    }
    let contents = """
    {
      "images" : [
    \(entries.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
    try! contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print(folder.lastPathComponent)
}
