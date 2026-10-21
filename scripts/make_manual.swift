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

// Creates the manual of Schreibmaschine, in the style of the other apps' manuals. The texts
// live in docs/handbuch/de.md and en.md; screenshots are taken from docs/screenshots.
// Usage (from the project folder): swift scripts/make_manual.swift [en]
//   without an argument: docs/handbuch/de.md → docs/Schreibmaschine-Handbuch.pdf (German)
//   with "en":           docs/handbuch/en.md → docs/Schreibmaschine-Manual.pdf (English)
// A copy goes to Resources/, from where "Help → Schreibmaschine Manual" opens it in the app.

import AppKit
import PDFKit

// MARK: - Language

let english = CommandLine.arguments.contains("en")

let sourcePath = english ? "docs/handbuch/en.md" : "docs/handbuch/de.md"
let outputPath = english ? "docs/Schreibmaschine-Manual.pdf" : "docs/Schreibmaschine-Handbuch.pdf"

// MARK: - Look

/// The steel blue of the app icon and the accent color.
let accent = NSColor(srgbRed: 0.247, green: 0.435, blue: 0.706, alpha: 1)
let ink = NSColor(white: 0.1, alpha: 1)
let quiet = NSColor(white: 0.42, alpha: 1)
let paper = NSColor.white

let pageSize = CGSize(width: 595, height: 842)   // A4
let margin: CGFloat = 70
let contentWidth = pageSize.width - 2 * margin
let bottomMargin: CGFloat = 78

func paragraphStyle(_ spacing: CGFloat, alignment: NSTextAlignment = .left, lineSpacing: CGFloat = 3,
                    hyphenates: Bool = true) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.paragraphSpacing = spacing
    style.alignment = alignment
    style.lineSpacing = lineSpacing
    style.hyphenationFactor = hyphenates ? 1 : 0
    return style
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = ink, spacing: CGFloat = 0, alignment: NSTextAlignment = .left,
          lineSpacing: CGFloat = 3, hyphenates: Bool = true) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraphStyle(spacing, alignment: alignment, lineSpacing: lineSpacing, hyphenates: hyphenates),
    ])
}

// MARK: - Document model

enum Block {
    case chapter(String)        // starts a new page and an outline entry
    case heading(String)
    case body(String)
    case bullet(String)
    case note(String)           // text in a tinted box
    case picture(path: String, caption: String)
    case shortcuts([(String, String)])
}

/// Reads the handbook text, see the comment at the top of the file for its format:
/// the fields for the title page first, then the chapters. A field may go on over several
/// lines; every line that does not start with a new field name continues the previous one.
func readHandbook(_ path: String) -> (fields: [String: String], blocks: [Block]) {
    guard var source = try? String(contentsOfFile: path, encoding: .utf8) else {
        fatalError("\(path) nicht gefunden – aus dem Projektordner aufrufen")
    }
    while let open = source.range(of: "<!--"), let close = source.range(of: "-->", range: open.upperBound..<source.endIndex) {
        source.removeSubrange(open.lowerBound..<close.upperBound)
    }
    var fields: [String: String] = [:]
    var blocks: [Block] = []
    var paragraph: [String] = []
    var rows: [(String, String)] = []
    var inContent = false
    var lastField = ""

    func flush() {
        if !paragraph.isEmpty {
            let joined = paragraph.joined(separator: " ")
            if joined.hasPrefix("- ") {
                blocks.append(.bullet(String(joined.dropFirst(2))))
            } else if joined.hasPrefix("> ") {
                blocks.append(.note(String(joined.dropFirst(2))))
            } else {
                blocks.append(.body(joined))
            }
            paragraph = []
        }
        if !rows.isEmpty {
            blocks.append(.shortcuts(rows))
            rows = []
        }
    }

    for rawLine in source.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            flush()
        } else if line.hasPrefix("# ") {
            flush()
            inContent = true
            blocks.append(.chapter(String(line.dropFirst(2))))
        } else if !inContent {
            if let colon = line.firstIndex(of: ":"),
               line[..<colon].allSatisfy(\.isLetter), !line[..<colon].isEmpty {
                lastField = String(line[..<colon])
                fields[lastField] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            } else if !lastField.isEmpty {
                fields[lastField, default: ""] += " " + line
            }
        } else if line.hasPrefix("## ") {
            flush()
            blocks.append(.heading(String(line.dropFirst(3))))
        } else if line.hasPrefix("!["), let close = line.firstIndex(of: "]"),
                  let open = line[close...].firstIndex(of: "("), line.hasSuffix(")") {
            flush()
            let caption = String(line[line.index(line.startIndex, offsetBy: 2)..<close])
            let path = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
            blocks.append(.picture(path: path, caption: caption))
        } else if line.hasPrefix("|") {
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.count == 2 { rows.append((cells[0], cells[1])) }
        } else if line.hasPrefix("- ") || line.hasPrefix("> ") {
            // Each bullet and each note line starts a block of its own.
            flush()
            paragraph = [line]
        } else if paragraph.first?.hasPrefix("> ") == true, line.hasPrefix(">") {
            paragraph.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
        } else {
            paragraph.append(line)
        }
    }
    flush()
    return (fields, blocks)
}

let handbook = readHandbook(sourcePath)
let blocks = handbook.blocks

func field(_ name: String) -> String {
    guard let value = handbook.fields[name] else { fatalError("\(sourcePath): „\(name):“ fehlt") }
    return value
}

let coverSubtitle = field("Untertitel")
let coverClaim = field("Leitsatz")
let coverIntro = field("Einleitung")
let documentTitle = field("Dokumenttitel")
let documentSubject = field("Thema")

// MARK: - Rendering

var outline: [(title: String, page: Int)] = []
var pageNumber = 0
var pageOpen = false
var y: CGFloat = 0
var runningHead = ""

let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
var mediaBox = CGRect(origin: .zero, size: pageSize)
let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil)!

func beginPage() {
    ctx.beginPDFPage(nil)
    pageOpen = true
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    paper.setFill()
    CGRect(origin: .zero, size: pageSize).fill()
    pageNumber += 1
    y = pageSize.height - margin
}

func endPage() {
    guard pageOpen else { return }
    pageOpen = false
    // The title page carries neither a running head nor a page number.
    if pageNumber == 1 {
        ctx.endPDFPage()
        return
    }
    if !runningHead.isEmpty {
        text(runningHead, size: 8.5, color: quiet)
            .draw(at: NSPoint(x: margin, y: pageSize.height - margin + 24))
        accent.withAlphaComponent(0.25).setFill()
        CGRect(x: margin, y: pageSize.height - margin + 18, width: contentWidth, height: 0.7).fill()
    }
    let number = text("\(pageNumber)", size: 9, color: quiet)
    number.draw(at: NSPoint(x: (pageSize.width - number.size().width) / 2, y: bottomMargin - 34))
    ctx.endPDFPage()
}

/// Text laid out at a width. Measuring and drawing go through the same layout: drawing an
/// attributed string breaks justified, hyphenated lines differently at times and then needs
/// one line more than measured, which is cut off.
func layout(_ string: NSAttributedString, width: CGFloat) -> (NSLayoutManager, NSTextContainer, NSTextStorage) {
    let storage = NSTextStorage(attributedString: string)
    let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    let manager = NSLayoutManager()
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    return (manager, container, storage)
}

func height(_ string: NSAttributedString, width: CGFloat = contentWidth) -> CGFloat {
    let (manager, container, storage) = layout(string, width: width)
    // The layout manager holds its text only weakly.
    return withExtendedLifetime(storage) { ceil(manager.usedRect(for: container).height) + 3 }
}

/// Draws the text with its top left corner at the point, in the page's coordinates.
func draw(_ string: NSAttributedString, x: CGFloat, top: CGFloat, width: CGFloat) {
    let (manager, container, storage) = layout(string, width: width)
    ctx.saveGState()
    ctx.translateBy(x: x, y: top)
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    manager.drawGlyphs(forGlyphRange: manager.glyphRange(for: container), at: .zero)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    ctx.restoreGState()
    withExtendedLifetime(storage) {}
}

func place(_ string: NSAttributedString, indent: CGFloat = 0, gap: CGFloat = 0) {
    let width = contentWidth - indent
    let needed = height(string, width: width)
    if y - needed < bottomMargin {
        endPage()
        beginPage()
    }
    draw(string, x: margin + indent, top: y, width: width)
    y -= needed + gap
}

func titlePage() {
    beginPage()
    accent.setFill()
    CGRect(x: 0, y: pageSize.height - 250, width: pageSize.width, height: 250).fill()

    let title = text("Schreibmaschine", size: 46, weight: .bold, color: .white)
    title.draw(at: NSPoint(x: margin, y: pageSize.height - 150))
    // The title page breaks lines only between words: centered short texts look better whole.
    let subtitle = text(coverSubtitle, size: 15, color: NSColor(white: 1, alpha: 0.9), hyphenates: false)
    subtitle.draw(at: NSPoint(x: margin + 3, y: pageSize.height - 185))

    if let icon = NSImage(contentsOfFile: "Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png") {
        icon.draw(in: CGRect(x: (pageSize.width - 190) / 2, y: 380, width: 190, height: 190))
    }

    let claim = text(coverClaim, size: 19, weight: .semibold, color: accent, alignment: .center, hyphenates: false)
    claim.draw(with: CGRect(x: margin, y: 310, width: contentWidth, height: 40), options: [.usesLineFragmentOrigin])

    let intro = text(coverIntro,
                     size: 12, color: quiet, alignment: .center, lineSpacing: 4, hyphenates: false)
    intro.draw(with: CGRect(x: margin + 40, y: 230, width: contentWidth - 80, height: 70), options: [.usesLineFragmentOrigin, .usesFontLeading])

    let footer = text("Version 1.0 · stefanradermacher.com", size: 9.5, color: quiet, alignment: .center)
    footer.draw(with: CGRect(x: margin, y: 120, width: contentWidth, height: 20), options: [.usesLineFragmentOrigin])
    endPage()
}

func shortcutTable(_ rows: [(String, String)]) {
    let rowHeight: CGFloat = 22
    for (index, row) in rows.enumerated() {
        if y - rowHeight < bottomMargin {
            endPage()
            beginPage()
        }
        if index % 2 == 0 {
            NSColor(white: 0.96, alpha: 1).setFill()
            CGRect(x: margin - 8, y: y - rowHeight + 4, width: contentWidth + 16, height: rowHeight).fill()
        }
        text(row.0, size: 11).draw(at: NSPoint(x: margin, y: y - rowHeight + 10))
        let keys = text(row.1, size: 11, weight: .medium, color: accent)
        keys.draw(at: NSPoint(x: pageSize.width - margin - keys.size().width, y: y - rowHeight + 10))
        y -= rowHeight
    }
    y -= 10
}

func noteBox(_ string: String) {
    let content = text(string, size: 11, color: NSColor(white: 0.25, alpha: 1), lineSpacing: 3.5)
    let inner = contentWidth - 34
    let needed = height(content, width: inner) + 28
    if y - needed < bottomMargin {
        endPage()
        beginPage()
    }
    let box = CGRect(x: margin, y: y - needed, width: contentWidth, height: needed)
    NSColor(srgbRed: 0.92, green: 0.945, blue: 0.98, alpha: 1).setFill()
    NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
    accent.setFill()
    CGRect(x: box.minX, y: box.minY, width: 3.5, height: box.height).fill()
    draw(content, x: box.minX + 20, top: box.maxY - 14, width: inner)
    y -= needed + 16
}

/// The screenshot at 1800 pixels wide as a JPEG, so that the PDF stays small: a JPEG image is
/// embedded as it is, a PNG screenshot would be embedded at full size without loss.
func compressed(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 1800,
          ] as CFDictionary)
    else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, small, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
    guard CGImageDestinationFinalize(destination),
          let jpeg = CGImageSourceCreateWithData(data, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(jpeg, 0, nil)
}

/// A screenshot across the text width with a thin frame and a caption. A missing file is
/// skipped with a warning, so the manual can be made before the screenshots exist.
func picture(_ path: String, caption: String) {
    guard let image = compressed(path) else {
        print("Hinweis: \(path) fehlt, das Bild wird ausgelassen")
        return
    }
    let width = contentWidth
    let imageHeight = width * CGFloat(image.height) / CGFloat(image.width)
    let label = text(caption, size: 9.5, color: quiet, alignment: .center)
    let labelHeight = caption.isEmpty ? 0 : height(label) + 4
    if y - imageHeight - labelHeight < bottomMargin {
        endPage()
        beginPage()
    }
    let frame = CGRect(x: margin, y: y - imageHeight, width: width, height: imageHeight)
    ctx.draw(image, in: frame)
    NSColor(white: 0.82, alpha: 1).setStroke()
    NSBezierPath(rect: frame.insetBy(dx: -0.25, dy: -0.25)).stroke()
    y -= imageHeight + 6
    if !caption.isEmpty {
        label.draw(with: CGRect(x: margin, y: y - labelHeight, width: width, height: labelHeight),
                   options: [.usesLineFragmentOrigin, .usesFontLeading])
        y -= labelHeight
    }
    y -= 12
}

func isBullet(_ block: Block) -> Bool {
    if case .bullet = block { return true }
    return false
}

titlePage()

for (index, block) in blocks.enumerated() {
    // A list is not torn apart: if its points do not all fit, it starts on the next page.
    if case .bullet = block, index == 0 || !isBullet(blocks[index - 1]) {
        let run = blocks[index...].prefix(while: isBullet)
        let needed = run.reduce(CGFloat(0)) { total, next in
            guard case .bullet(let string) = next else { return total }
            return total + height(text(string, size: 11.5, lineSpacing: 3.5), width: contentWidth - 18) + 7
        }
        if y - needed < bottomMargin && needed < pageSize.height - margin - bottomMargin {
            endPage()
            beginPage()
        }
    }
    switch block {
    case .chapter(let title):
        endPage()
        runningHead = title
        beginPage()
        outline.append((title, pageNumber))
        place(text(title, size: 27, weight: .bold, color: accent), gap: 6)
        accent.withAlphaComponent(0.3).setFill()
        CGRect(x: margin, y: y + 2, width: 70, height: 2.5).fill()
        y -= 18
    case .heading(let title):
        y -= 6
        // A heading never stays alone at the foot of a page: it needs room for a few lines below.
        if y - 90 < bottomMargin {
            endPage()
            beginPage()
        }
        place(text(title, size: 14, weight: .semibold), gap: 6)
    case .body(let string):
        place(text(string, size: 11.5, alignment: .justified, lineSpacing: 3.5), gap: 12)
    case .bullet(let string):
        let dot = text("•", size: 11.5, color: accent)
        let line = text(string, size: 11.5, lineSpacing: 3.5)
        let needed = height(line, width: contentWidth - 18)
        if y - needed < bottomMargin {
            endPage()
            beginPage()
        }
        dot.draw(at: NSPoint(x: margin, y: y - needed + (needed - 14)))
        draw(line, x: margin + 18, top: y, width: contentWidth - 18)
        y -= needed + 7
    case .note(let string):
        y -= 4
        noteBox(string)
    case .picture(let path, let caption):
        picture(path, caption: caption)
    case .shortcuts(let rows):
        shortcutTable(rows)
    }
}
endPage()

// Outline, so the sidebar has something to show
let children = outline.map { entry -> [String: Any] in
    ["Title": entry.title, "Destination": entry.page]
}
CGPDFContextSetOutline(ctx, ["Children": children] as CFDictionary)
ctx.closePDF()

// Title and author for the document information
if let document = PDFDocument(url: url) {
    document.documentAttributes = [
        PDFDocumentAttribute.titleAttribute: documentTitle,
        PDFDocumentAttribute.authorAttribute: "Stefan Radermacher",
        PDFDocumentAttribute.subjectAttribute: documentSubject,
        PDFDocumentAttribute.creatorAttribute: "Schreibmaschine",
    ]
    let temporary = url.deletingLastPathComponent().appendingPathComponent("tmp-handbuch.pdf")
    if document.write(to: temporary) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.moveItem(at: temporary, to: url)
    }
}
// The same file in the app bundle, so the manual in the app always matches the one in docs/.
let bundleCopy = URL(fileURLWithPath: "Resources").appendingPathComponent(url.lastPathComponent)
try? FileManager.default.removeItem(at: bundleCopy)
try? FileManager.default.copyItem(at: url, to: bundleCopy)
print("\(outputPath) — \(pageNumber) Seiten, \(outline.count) Kapitel, Kopie in \(bundleCopy.relativePath)")
