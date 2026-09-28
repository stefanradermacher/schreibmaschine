import AppKit

/// Text attributes of the editor: one font, tab stops every `tabWidth` spaces.
enum EditorStyle {
    static func attributes(font: NSFont = Preferences.font) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .paragraphStyle: paragraphStyle(font: font),
            .foregroundColor: NSColor.textColor,
        ]
    }

    static func paragraphStyle(font: NSFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = spaceWidth(of: font) * CGFloat(Preferences.tabWidthValue)
        return style
    }

    static func spaceWidth(of font: NSFont) -> CGFloat {
        (" " as NSString).size(withAttributes: [.font: font]).width
    }

    /// The insertion point in the orange of the app icon.
    static let insertionPointColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 1, green: 0.55, blue: 0.3, alpha: 1)
            : NSColor(srgbRed: 0.91, green: 0.44, blue: 0.18, alpha: 1)
    }

    /// Background of the line with the insertion point.
    static let currentLineColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.06)
            : NSColor(white: 0, alpha: 0.045)
    }
}

/// The editor's text view: plain text, indenting with spaces or tabs, keeping the indentation
/// of the previous line, highlighting the line with the insertion point.
final class EditorTextView: NSTextView {
    var highlightsCurrentLine = true { didSet { needsDisplay = true } }
    /// Esc in the text; returns true if it was used, for instance to close the find bar.
    var onCancel: (() -> Bool)?

    override func cancelOperation(_ sender: Any?) {
        if onCancel?() == true { return }
        super.cancelOperation(sender)
    }

    /// Draws the laid-out paragraphs again without laying them out anew. TextKit 2 does not
    /// redraw them by itself when rendering attributes or drawing options change, and a new
    /// layout would make it estimate the heights again, so the view would jump.
    func redrawFragments() {
        func redraw(_ view: NSView) {
            view.needsDisplay = true
            view.layer?.sublayers?.forEach { $0.setNeedsDisplay() }
            view.subviews.forEach(redraw)
        }
        redraw(self)
    }

    // MARK: - Current line

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard highlightsCurrentLine, let lineRect = currentLineRect() else { return }
        EditorStyle.currentLineColor.setFill()
        lineRect.intersection(rect).fill()
    }

    /// The visual line with the insertion point, across the whole width.
    private func currentLineRect() -> NSRect? {
        let selection = selectedRange()
        guard selectedRanges.count == 1, selection.length == 0,
              let layoutManager = textLayoutManager,
              let content = layoutManager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: selection.location)
        else { return nil }
        var lineFrame: CGRect?
        layoutManager.enumerateTextSegments(in: NSTextRange(location: location), type: .standard, options: [.rangeNotRequired]) { _, frame, _, _ in
            lineFrame = frame
            return false
        }
        guard let lineFrame else { return nil }
        return NSRect(x: 0, y: lineFrame.minY + textContainerOrigin.y, width: bounds.width, height: lineFrame.height)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if highlightsCurrentLine { setNeedsDisplay(visibleRect) }
    }

    // MARK: - Indentation

    override func insertTab(_ sender: Any?) {
        guard Preferences.indentsWithSpacesValue, selectedRange().length == 0 else { return super.insertTab(sender) }
        let width = Preferences.tabWidthValue
        let count = width - column(at: selectedRange().location) % width
        insertText(String(repeating: " ", count: count), replacementRange: selectedRange())
    }

    override func insertNewline(_ sender: Any?) {
        guard Preferences.autoIndentsValue else { return super.insertNewline(sender) }
        let text = string as NSString
        let selection = selectedRange()
        let lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
        var indentEnd = lineStart
        while indentEnd < selection.location, [0x20, 0x09].contains(text.character(at: indentEnd)) {
            indentEnd += 1
        }
        let indent = text.substring(with: NSRange(location: lineStart, length: indentEnd - lineStart))
        insertText("\n" + indent, replacementRange: selection)
    }

    /// With spaces as indentation, backspace in the indentation goes back to the previous tab stop.
    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        guard Preferences.indentsWithSpacesValue, selectedRanges.count == 1, selection.length == 0, selection.location > 0 else {
            return super.deleteBackward(sender)
        }
        let text = string as NSString
        let lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let before = selection.location - lineStart
        guard before > 1, text.substring(with: NSRange(location: lineStart, length: before)).allSatisfy({ $0 == " " }) else {
            return super.deleteBackward(sender)
        }
        let width = Preferences.tabWidthValue
        let count = before % width == 0 ? width : before % width
        let range = NSRange(location: selection.location - count, length: count)
        if shouldChangeText(in: range, replacementString: "") {
            textStorage?.replaceCharacters(in: range, with: "")
            didChangeText()
        }
    }

    /// Visual column of a location in its line, with tabs expanded.
    private func column(at location: Int) -> Int {
        let text = string as NSString
        let lineStart = text.lineRange(for: NSRange(location: location, length: 0)).location
        let width = Preferences.tabWidthValue
        var column = 0
        for index in lineStart..<location {
            column = text.character(at: index) == 0x09 ? (column / width + 1) * width : column + 1
        }
        return column
    }

    // MARK: - Pasting

    /// Pasted and dropped text gets LF line breaks like the rest of the document.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == .string, let text = pboard.string(forType: .string), text.utf16.contains(0x0D) {
            let range = rangeForUserTextChange
            guard range.location != NSNotFound else { return false }
            insertText(text.normalizingLineEndings, replacementRange: range)
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }
}
