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
    /// The Text menu command being run, for the name of its undo step.
    var currentCommandTitle: String?

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(performTextCommand(_:)), #selector(expandSelection(_:)), #selector(shrinkSelection(_:)):
            return isEditable || item.action != #selector(performTextCommand(_:))
        case #selector(repeatTextCommand(_:)):
            if let last = TextCommands.last {
                item.title = String(localized: "Erneut ausführen: \(last.command.title.replacingOccurrences(of: " …", with: ""))")
                return isEditable
            }
            item.title = String(localized: "Erneut ausführen")
            return false
        default:
            return super.validateMenuItem(item)
        }
    }

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
        // With a selection over several lines, ⇥ indents them, as in most editors.
        let selection = selectedRange()
        if selection.length > 0, (string as NSString).substring(with: selection).contains("\n") {
            currentCommandTitle = String(localized: "Einrücken")
            indentLines()
            currentCommandTitle = nil
            return
        }
        guard Preferences.indentsWithSpacesValue, selectedRange().length == 0 else { return super.insertTab(sender) }
        let width = Preferences.tabWidthValue
        let count = width - column(at: selectedRange().location) % width
        insertText(String(repeating: " ", count: count), replacementRange: selectedRange())
    }

    /// ⇧⇥ outdents the current line or the lines of the selection.
    override func insertBacktab(_ sender: Any?) {
        currentCommandTitle = String(localized: "Ausrücken")
        outdentLines()
        currentCommandTitle = nil
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

    // MARK: - Expanding the selection

    private var selectionHistory: [NSRange] = []
    private var expandedSelection: NSRange?

    /// ⌥↑: word, text in quotes, text in brackets, line, paragraph, document — each step the
    /// next larger unit around the selection.
    @objc func expandSelection(_ sender: Any?) {
        let current = selectedRange()
        if expandedSelection != current { selectionHistory = [] }
        guard let next = enclosingRanges(of: current)
            .filter({ NSEqualRanges(NSUnionRange($0, current), $0) && $0.length > current.length })
            .min(by: { $0.length < $1.length })
        else { return NSSound.beep() }
        selectionHistory.append(current)
        setSelectedRange(next)
        expandedSelection = next
    }

    /// ⌥↓: back to the selection before the last ⌥↑.
    @objc func shrinkSelection(_ sender: Any?) {
        guard expandedSelection == selectedRange(), let previous = selectionHistory.popLast() else { return NSSound.beep() }
        setSelectedRange(previous)
        expandedSelection = previous
    }

    private func enclosingRanges(of selection: NSRange) -> [NSRange] {
        let text = string as NSString
        var ranges: [NSRange] = [wordRange(at: selection.location)]
        let line = text.lineRange(for: selection)
        var lineContent = line
        while lineContent.length > 0, [0x0A, 0x0D].contains(text.character(at: lineContent.upperBound - 1)) { lineContent.length -= 1 }
        var trimmed = lineContent
        while trimmed.length > 0, [0x20, 0x09].contains(text.character(at: trimmed.location)) { trimmed.location += 1; trimmed.length -= 1 }
        ranges += [trimmed, lineContent, line]

        // Quotes on the same line around the selection.
        for quote in [0x22, 0x27, 0x60] as [unichar] {
            var positions: [Int] = []
            for index in lineContent.location..<lineContent.upperBound where text.character(at: index) == quote {
                if index > lineContent.location, text.character(at: index - 1) == 0x5C { continue }
                positions.append(index)
            }
            for pair in stride(from: 0, to: positions.count - 1, by: 2) {
                let open = positions[pair], close = positions[pair + 1]
                ranges.append(NSRange(location: open + 1, length: close - open - 1))
                ranges.append(NSRange(location: open, length: close - open + 1))
            }
        }

        // Brackets around the selection, nested ones skipped.
        let pairs: [unichar: unichar] = [0x28: 0x29, 0x5B: 0x5D, 0x7B: 0x7D]
        var depth: [unichar: Int] = [:]
        var index = selection.location - 1
        let limit = max(0, selection.location - 200_000)
        while index >= limit {
            let character = text.character(at: index)
            if let closer = pairs[character] {
                if depth[closer, default: 0] == 0 {
                    if let close = matchingClose(of: character, closer: closer, from: max(selection.upperBound, index + 1), in: text) {
                        ranges.append(NSRange(location: index + 1, length: close - index - 1))
                        ranges.append(NSRange(location: index, length: close - index + 1))
                    }
                } else {
                    depth[closer]! -= 1
                }
            } else if pairs.values.contains(character) {
                depth[character, default: 0] += 1
            }
            index -= 1
        }

        // The paragraph and the whole text.
        var start = line.location
        while start > 0 {
            let previous = text.lineRange(for: NSRange(location: start - 1, length: 0))
            if text.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
            start = previous.location
        }
        var end = line.upperBound
        while end < text.length {
            let next = text.lineRange(for: NSRange(location: end, length: 0))
            if text.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
            end = next.upperBound
        }
        ranges.append(NSRange(location: start, length: end - start))
        ranges.append(NSRange(location: 0, length: text.length))
        return ranges.filter { $0.location != NSNotFound && $0.length >= 0 }
    }

    private func matchingClose(of opener: unichar, closer: unichar, from start: Int, in text: NSString) -> Int? {
        var depth = 0
        var index = start
        let limit = min(text.length, start + 200_000)
        while index < limit {
            let character = text.character(at: index)
            if character == opener { depth += 1 }
            else if character == closer {
                if depth == 0 { return index }
                depth -= 1
            }
            index += 1
        }
        return nil
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
