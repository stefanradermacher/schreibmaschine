import AppKit

/// Line numbers beside the text. A wrapped line gets its number on its first row only.
/// Lines with a bookmark are marked; a click on a line number sets or removes one.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    private let lineIndex: LineIndex
    private let padding: CGFloat = 8
    var bookmarkedLines: () -> [Int] = { [] }
    var onClickLine: ((Int) -> Void)?

    enum FoldMark { case none, open, folded }
    var foldMark: (Int) -> FoldMark = { _ in .none }
    var foldedHeads: () -> [Int] = { [] }
    var onClickFold: ((Int) -> Void)?
    /// Room for the fold marks right of the numbers.
    private let foldWidth: CGFloat = 12
    /// The marks of open blocks show while the mouse is over the ruler, as in Xcode.
    private var isMouseInside = false {
        didSet { if isMouseInside != oldValue { needsDisplay = true } }
    }

    var font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular) {
        didSet { updateThickness(force: true) }
    }

    init(textView: NSTextView, lineIndex: LineIndex) {
        self.textView = textView
        self.lineIndex = lineIndex
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        // Since macOS 14 views draw beyond their bounds unless told otherwise; the ruler
        // would paint over the text.
        clipsToBounds = true
        updateThickness(force: true)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var digits = 0

    /// Wide enough for the largest line number, at least three digits.
    func updateThickness(force: Bool = false) {
        let needed = max(3, String(lineIndex.lineCount).count)
        guard force || needed != digits else { return }
        digits = needed
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        ruleThickness = ceil(CGFloat(digits) * digitWidth + 2 * padding + foldWidth)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.textLayoutManager,
              let content = layoutManager.textContentManager
        else { return }

        NSColor.textBackgroundColor.setFill()
        rect.intersection(bounds).fill()

        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin
        let selection = textView.selectedRange()
        let currentLine = lineIndex.lineNumber(at: selection.location)
        let documentStart = content.documentRange.location
        let endsWithNewline = (textView.string as NSString).hasSuffix("\n") || textView.string.isEmpty

        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let current: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]

        let bookmarks = Set(bookmarkedLines())
        let folded = Set(foldedHeads())
        let marked: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]

        func drawNumber(_ number: Int, lineTop: CGFloat, lineHeight: CGFloat, baseline: CGFloat) {
            let label = String(number) as NSString
            let isMarked = bookmarks.contains(number)
            let attributes = isMarked ? marked : number == currentLine ? current : normal
            let size = label.size(withAttributes: attributes)
            let y = convert(NSPoint(x: 0, y: lineTop + origin.y), from: textView).y
            if isMarked { drawBookmark(top: y, height: lineHeight) }
            if folded.contains(number) {
                drawFoldMark(.folded, top: y, height: lineHeight)
            } else if isMouseInside {
                drawFoldMark(foldMark(number), top: y, height: lineHeight)
            }
            // Align the number's baseline with the text's.
            let top = y + baseline - font.ascender
            label.draw(at: NSPoint(x: ruleThickness - foldWidth - padding - size.width, y: top), withAttributes: attributes)
        }

        let start = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: visible.minY - origin.y))?.rangeInElement.location
            ?? documentStart
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY > visible.maxY { return false }
            let offset = content.offset(from: documentStart, to: fragment.rangeInElement.location)
            let number = lineIndex.lineNumber(at: offset)
            let lines = fragment.textLineFragments
            if let first = lines.first {
                drawNumber(number, lineTop: frame.minY + first.typographicBounds.minY, lineHeight: first.typographicBounds.height, baseline: first.glyphOrigin.y)
            }
            // The empty last line after a final line break.
            if lines.count > 1, let last = lines.last, last.characterRange.length == 0,
               fragment.rangeInElement.endLocation.compare(content.documentRange.endLocation) != .orderedAscending,
               endsWithNewline {
                drawNumber(number + 1, lineTop: frame.minY + last.typographicBounds.minY, lineHeight: last.typographicBounds.height, baseline: last.glyphOrigin.y)
            }
            return true
        }

        // An empty document has no fragment; its only line still gets a number.
        if textView.string.isEmpty {
            drawNumber(1, lineTop: 0, lineHeight: NSLayoutManager().defaultLineHeight(for: textView.font ?? font), baseline: (textView.font ?? font).ascender)
        }
    }

    /// A tag pointing at the text, in the accent color, as Xcode marks breakpoints.
    private func drawBookmark(top: CGFloat, height: CGFloat) {
        let rect = NSRect(x: 2, y: top + 1, width: ruleThickness - foldWidth - 2, height: max(height - 2, 4))
        let tip = min(rect.height / 2, 6)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + 2, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - tip, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        path.line(to: NSPoint(x: rect.maxX - tip, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + 2, y: rect.maxY))
        path.appendArc(withCenter: NSPoint(x: rect.minX + 2, y: rect.maxY - 2), radius: 2, startAngle: 90, endAngle: 180)
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + 2))
        path.appendArc(withCenter: NSPoint(x: rect.minX + 2, y: rect.minY + 2), radius: 2, startAngle: 180, endAngle: 270)
        path.close()
        NSColor.controlAccentColor.setFill()
        path.fill()
    }

    /// A chevron: pointing down beside an open block, to the right beside a folded one.
    private func drawFoldMark(_ mark: FoldMark, top: CGFloat, height: CGFloat) {
        guard mark == .folded || (mark == .open && isMouseInside) else { return }
        let center = NSPoint(x: ruleThickness - foldWidth / 2 - 1, y: top + height / 2)
        let size: CGFloat = 3.5
        let path = NSBezierPath()
        if mark == .folded {
            path.move(to: NSPoint(x: center.x - size / 2, y: center.y - size))
            path.line(to: NSPoint(x: center.x + size / 2, y: center.y))
            path.line(to: NSPoint(x: center.x - size / 2, y: center.y + size))
        } else {
            path.move(to: NSPoint(x: center.x - size, y: center.y - size / 2))
            path.line(to: NSPoint(x: center.x, y: center.y + size / 2))
            path.line(to: NSPoint(x: center.x + size, y: center.y - size / 2))
        }
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        (mark == .folded ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setStroke()
        path.stroke()
    }

    // MARK: - Clicks

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let line = line(at: point) else { return super.mouseDown(with: event) }
        if point.x >= ruleThickness - foldWidth - 2 {
            if foldMark(line) != .none { onClickFold?(line) }
        } else {
            onClickLine?(line)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isMouseInside = true }
    override func mouseExited(with event: NSEvent) { isMouseInside = false }

    /// The line shown at a point of the ruler.
    private func line(at point: NSPoint) -> Int? {
        guard let textView, let layoutManager = textView.textLayoutManager, let content = layoutManager.textContentManager else { return nil }
        let inText = textView.convert(point, from: self)
        let origin = textView.textContainerOrigin
        guard let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: inText.y - origin.y)) else {
            return textView.string.isEmpty ? 1 : nil
        }
        let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let line = lineIndex.lineNumber(at: offset)
        // The empty last line after a final line break has no paragraph of its own.
        if let last = fragment.textLineFragments.last, fragment.textLineFragments.count > 1, last.characterRange.length == 0,
           inText.y - origin.y >= fragment.layoutFragmentFrame.minY + last.typographicBounds.minY {
            return line + 1
        }
        return line
    }
}
