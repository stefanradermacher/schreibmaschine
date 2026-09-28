import AppKit

/// Line numbers beside the text. A wrapped line gets its number on its first row only.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    private let lineIndex: LineIndex
    private let padding: CGFloat = 8

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
        ruleThickness = ceil(CGFloat(digits) * digitWidth + 2 * padding)
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

        func drawNumber(_ number: Int, lineTop: CGFloat, baseline: CGFloat) {
            let label = String(number) as NSString
            let attributes = number == currentLine ? current : normal
            let size = label.size(withAttributes: attributes)
            let y = convert(NSPoint(x: 0, y: lineTop + origin.y), from: textView).y
            // Align the number's baseline with the text's.
            let top = y + baseline - font.ascender
            label.draw(at: NSPoint(x: ruleThickness - padding - size.width, y: top), withAttributes: attributes)
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
                drawNumber(number, lineTop: frame.minY + first.typographicBounds.minY, baseline: first.glyphOrigin.y)
            }
            // The empty last line after a final line break.
            if lines.count > 1, let last = lines.last, last.characterRange.length == 0,
               fragment.rangeInElement.endLocation.compare(content.documentRange.endLocation) != .orderedAscending,
               endsWithNewline {
                drawNumber(number + 1, lineTop: frame.minY + last.typographicBounds.minY, baseline: last.glyphOrigin.y)
            }
            return true
        }

        // An empty document has no fragment; its only line still gets a number.
        if textView.string.isEmpty {
            drawNumber(1, lineTop: 0, baseline: (textView.font ?? font).ascender)
        }
    }
}
