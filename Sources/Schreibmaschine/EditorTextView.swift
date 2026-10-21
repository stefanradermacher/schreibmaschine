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

import AppKit

/// Text attributes of the editor: one font, tab stops every `tabWidth` spaces, and lines
/// `lineHeight` times as high as the font needs, with the text in the middle of each line.
enum EditorStyle {
    static func attributes(font: NSFont = Preferences.font, tabWidth: Int = Preferences.tabWidthValue,
                           lineHeight: Double = Preferences.lineHeightValue) -> [NSAttributedString.Key: Any] {
        let natural = naturalLineHeight(of: font)
        let height = lineHeightPoints(font: font, multiple: lineHeight)
        return [
            .font: font,
            .paragraphStyle: paragraphStyle(font: font, tabWidth: tabWidth, lineHeight: lineHeight),
            .foregroundColor: NSColor.textColor,
            // TextKit puts the extra space above the text; half of it goes below instead.
            .baselineOffset: ((height - natural) / 2).rounded(),
        ]
    }

    static func paragraphStyle(font: NSFont, tabWidth: Int, lineHeight: Double = Preferences.lineHeightValue) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = spaceWidth(of: font) * CGFloat(tabWidth)
        let height = lineHeightPoints(font: font, multiple: lineHeight)
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        return style
    }

    static func naturalLineHeight(of font: NSFont) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: font)
    }

    static func lineHeightPoints(font: NSFont, multiple: Double) -> CGFloat {
        (naturalLineHeight(of: font) * CGFloat(multiple)).rounded()
    }

    /// Background of a bracket and its partner next to the insertion point.
    static let bracketColor = NSColor(name: nil) { appearance in
        NSColor.controlAccentColor.withAlphaComponent(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.35 : 0.22)
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
    /// The document's indentation and language, set by the editor.
    var indentation: () -> Indentation = { .preferred }
    var language: () -> LanguageDefinition? = { nil }
    /// A bracket next to the insertion point and its partner, drawn with a background.
    var bracketRanges: [NSRange] = [] {
        didSet { if bracketRanges != oldValue { setNeedsDisplay(visibleRect) } }
    }

    /// Ends of the head lines of folded blocks; a mark there stands for the hidden lines.
    var foldPlaceholders: () -> [Int] = { [] }
    var onClickFoldPlaceholder: ((Int) -> Void)?

    // Several insertion points (MultiCursor.swift).
    /// The ranges edited together while there are several; nil with one selection.
    var cursorRanges: [NSRange]?
    /// Set while the editor changes the selection itself, so it does not end the multiple insertion points.
    var isSettingCursors = false
    var caretIndicators: [NSTextInsertionIndicator] = []
    /// The occurrence ⌃G added last; the next one is searched after it.
    var lastAddedOccurrence: NSRange?

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(performTextCommand(_:)), #selector(expandSelection(_:)), #selector(shrinkSelection(_:)):
            return isEditable || item.action != #selector(performTextCommand(_:))
        case #selector(toggleComment(_:)):
            return isEditable && (language()?.lineComment != nil || language()?.blockComment != nil)
        case #selector(jumpToMatchingBracket(_:)):
            return bracketRanges.count == 2
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
        if hasMultipleCursors { return collapseCursors() }
        super.cancelOperation(sender)
    }

    // MARK: - Several insertion points

    override func doCommand(by selector: Selector) {
        var selector = Preferences.navigationMovesCaretValue ? Self.editorNavigation[selector] ?? selector : selector
        // NSTextView's own page movements do not move the insertion point under TextKit 2.
        selector = Self.pageMovements[selector] ?? selector
        if performMultiCursorCommand(selector) { return }
        super.doCommand(by: selector)
    }

    // MARK: - Navigation keys

    /// With "Page Up/Down, Home and End move the insertion point" on: Page Up and Down move the
    /// insertion point instead of only scrolling, and ⌘← goes to the smart start of the line.
    private static let editorNavigation: [Selector: Selector] = [
        #selector(scrollPageUp(_:)): #selector(movePageUp(_:)),
        #selector(scrollPageDown(_:)): #selector(movePageDown(_:)),
        #selector(moveToBeginningOfLine(_:)): #selector(moveToSmartLineStart(_:)),
        #selector(moveToLeftEndOfLine(_:)): #selector(moveToSmartLineStart(_:)),
        #selector(moveToBeginningOfLineAndModifySelection(_:)): #selector(moveToSmartLineStartAndModifySelection(_:)),
        #selector(moveToLeftEndOfLineAndModifySelection(_:)): #selector(moveToSmartLineStartAndModifySelection(_:)),
    ]

    /// Home and End are read from the key itself: macOS binds ⇧Home to the same command as ⌘⇧↑,
    /// which has to keep selecting to the start of the document. Home and End go to the start
    /// and end of the line, with ⌘ to the start and end of the document, with ⇧ selecting.
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard Preferences.navigationMovesCaretValue, !modifiers.contains(.option), !modifiers.contains(.control),
              let key = event.specialKey, key == .home || key == .end
        else { return super.keyDown(with: event) }
        let extend = modifiers.contains(.shift)
        let selector: Selector
        switch (key == .home, modifiers.contains(.command), extend) {
        case (true, true, false): selector = #selector(moveToBeginningOfDocument(_:))
        case (true, true, true): selector = #selector(moveToBeginningOfDocumentAndModifySelection(_:))
        case (false, true, false): selector = #selector(moveToEndOfDocument(_:))
        case (false, true, true): selector = #selector(moveToEndOfDocumentAndModifySelection(_:))
        case (true, false, false): selector = #selector(moveToSmartLineStart(_:))
        case (true, false, true): selector = #selector(moveToSmartLineStartAndModifySelection(_:))
        case (false, false, false): selector = #selector(moveToEndOfLine(_:))
        case (false, false, true): selector = #selector(moveToEndOfLineAndModifySelection(_:))
        }
        if performMultiCursorCommand(selector) { return }
        super.doCommand(by: selector)
    }

    private static let pageMovements: [Selector: Selector] = [
        #selector(pageUp(_:)): #selector(movePageUp(_:)),
        #selector(pageDown(_:)): #selector(movePageDown(_:)),
        #selector(pageUpAndModifySelection(_:)): #selector(movePageUpAndModifySelection(_:)),
        #selector(pageDownAndModifySelection(_:)): #selector(movePageDownAndModifySelection(_:)),
    ]

    @objc func movePageUp(_ sender: Any?) { movePage(down: false, extend: false) }
    @objc func movePageDown(_ sender: Any?) { movePage(down: true, extend: false) }
    @objc func movePageUpAndModifySelection(_ sender: Any?) { movePage(down: false, extend: true) }
    @objc func movePageDownAndModifySelection(_ sender: Any?) { movePage(down: true, extend: true) }

    /// Moves the insertion point by the lines that fit in the window, less one to keep one's
    /// bearings, and scrolls so that it stays at the same place in the window. Counted in lines,
    /// not points: below the visible part TextKit only estimates heights, so a point found
    /// there drifted by a line now and then.
    private func movePage(down: Bool, extend: Bool) {
        guard let scrollView = enclosingScrollView else { return }
        let before = selectedRange()
        let caret = down ? before.upperBound : before.location
        let caretFrame = caretRect(at: caret)
        let visible = scrollView.documentVisibleRect
        let offsetInWindow = caretFrame.minY - visible.minY
        let lineHeight = max(caretFrame.height, 1)
        let lines = max(Int(visible.height / lineHeight) - 1, 1)

        for _ in 0..<lines {
            switch (down, extend) {
            case (true, false): super.moveDown(nil)
            case (false, false): super.moveUp(nil)
            case (true, true): super.moveDownAndModifySelection(nil)
            case (false, true): super.moveUpAndModifySelection(nil)
            }
        }
        // On the first or last line already: on to the very start or end.
        let after = selectedRange()
        if after == before {
            let length = (string as NSString).length
            if extend {
                setSelectedRange(down ? NSRange(location: before.location, length: length - before.location)
                                      : NSRange(location: 0, length: before.upperBound))
            } else {
                setSelectedRange(NSRange(location: down ? length : 0, length: 0))
            }
        }

        let moved = selectedRange()
        let newCaret = down ? moved.upperBound : moved.location
        if let layoutManager = textLayoutManager, let content = layoutManager.textContentManager,
           let location = content.location(content.documentRange.location, offsetBy: newCaret) {
            layoutManager.ensureLayout(for: NSTextRange(location: location))
        }
        let maxY = max(frame.height - visible.height, 0)
        let y = (caretRect(at: newCaret).minY - offsetInWindow).clamped(to: 0...maxY)
        scrollView.contentView.scroll(to: NSPoint(x: visible.minX, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Home: the first character after the indentation, and from there the very start of the
    /// line. In a wrapped line it first goes to the start of the visual line.
    @objc func moveToSmartLineStart(_ sender: Any?) {
        setSelectedRange(NSRange(location: smartLineStart(from: selectedRange().location), length: 0))
        scrollRangeToVisible(selectedRange())
    }

    @objc func moveToSmartLineStartAndModifySelection(_ sender: Any?) {
        let selection = selectedRange()
        // The end that stays is the one away from the start of the line.
        let anchor = selection.upperBound
        let target = smartLineStart(from: selection.location)
        setSelectedRange(NSRange(location: min(target, anchor), length: abs(anchor - target)))
        scrollRangeToVisible(NSRange(location: target, length: 0))
    }

    private func smartLineStart(from caret: Int) -> Int {
        let text = string as NSString
        let lineStart = text.lineRange(for: NSRange(location: caret, length: 0)).location
        var indentEnd = lineStart
        while indentEnd < text.length, [0x20, 0x09].contains(text.character(at: indentEnd)) { indentEnd += 1 }
        // The start of the visual line, from TextKit.
        var visualStart = caret
        if let layoutManager = textLayoutManager, let content = layoutManager.textContentManager,
           let location = content.location(content.documentRange.location, offsetBy: caret),
           let fragment = layoutManager.textLayoutFragment(for: location) {
            let fragmentStart = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let inFragment = caret - fragmentStart
            if let line = fragment.textLineFragments.last(where: { $0.characterRange.location <= inFragment }) {
                visualStart = fragmentStart + line.characterRange.location
            }
        }
        if visualStart > indentEnd && caret != visualStart { return visualStart }
        return caret == indentEnd ? lineStart : indentEnd
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard hasMultipleCursors, replacementRange.location == NSNotFound else {
            return super.insertText(string, replacementRange: replacementRange)
        }
        let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        let ranges = editingRanges
        replaceRanges(ranges, with: ranges.map { _ in text })
    }

    /// Dead keys and input methods compose at one place only; with several insertion points the
    /// composed character is inserted at all of them when it is complete.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if hasMultipleCursors { return }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let (location, _) = foldPlaceholderRects().first(where: { $0.rect.contains(point) }) {
            onClickFoldPlaceholder?(location)
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if modifiers == .command { return addCursor(with: event) }
        if modifiers == .option { return selectBlock(with: event) }
        super.mouseDown(with: event)
    }

    override func copy(_ sender: Any?) {
        if copyMultiple(to: .general) { return }
        super.copy(sender)
    }

    override func cut(_ sender: Any?) {
        guard isEditable, copyMultiple(to: .general) else { return super.cut(sender) }
        let ranges = editingRanges
        replaceRanges(ranges, with: ranges.map { _ in "" })
    }

    override func paste(_ sender: Any?) {
        if isEditable, pasteMultiple(from: .general) { return }
        super.paste(sender)
    }

    /// Called when the view gets the keyboard focus; the editor makes its pane the active one.
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        defer { updateCaretIndicators() }
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        defer { updateCaretIndicators() }
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyStateDidChange(_:)), name: name, object: window)
        }
    }

    @objc private func keyStateDidChange(_ notification: Notification) {
        updateCaretIndicators()
    }

    // NSTextView holds back new layout while a window or split view is resized live, so lines
    // wrapped to the new width only when the mouse was released. Without its live-resize mode
    // they wrap as the edge moves, like in TextEdit.
    override func viewWillStartLiveResize() {}
    override func viewDidEndLiveResize() { onLiveResizeEnd?() }

    /// Called when a live resize of the window or a split view is over.
    var onLiveResizeEnd: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if cursorRanges != nil { updateCaretIndicators() }
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

    /// Extra backgrounds below the text, for the comparison: rectangles and their colors in the
    /// area to draw.
    var extraBackgrounds: ((NSRect) -> [(rect: NSRect, color: NSColor)])?

    /// Room above the first line, for the comparison when the other side starts with lines this
    /// one does not have.
    var extraTopSpace: CGFloat = 0 {
        didSet { if extraTopSpace != oldValue { needsLayout = true; needsDisplay = true } }
    }

    override var textContainerOrigin: NSPoint {
        var origin = super.textContainerOrigin
        origin.y += extraTopSpace
        return origin
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if let extraBackgrounds {
            for (frame, color) in extraBackgrounds(rect) {
                color.setFill()
                frame.intersection(rect).fill()
            }
        }
        if highlightsCurrentLine {
            EditorStyle.currentLineColor.setFill()
            for lineRect in currentLineRects() { lineRect.intersection(rect).fill() }
        }
        if !bracketRanges.isEmpty {
            EditorStyle.bracketColor.setFill()
            for range in bracketRanges {
                for frame in segmentFrames(of: range) {
                    NSBezierPath(roundedRect: frame.insetBy(dx: -1, dy: 0), xRadius: 3, yRadius: 3).fill()
                }
            }
        }
        drawFoldPlaceholders(in: rect)
    }

    // MARK: - Folds

    private func foldPlaceholderRects() -> [(location: Int, rect: NSRect)] {
        foldPlaceholders().compactMap { location in
            let caret = caretRect(at: location)
            guard caret.height > 0 else { return nil }
            let height = min(caret.height - 2, (font?.pointSize ?? 12) + 4)
            return (location, NSRect(x: caret.minX + 6, y: caret.midY - height / 2, width: max(22, height * 1.8), height: height))
        }
    }

    /// A rounded mark with an ellipsis behind a folded head line, as in Xcode.
    private func drawFoldPlaceholders(in dirtyRect: NSRect) {
        for (_, rect) in foldPlaceholderRects() where rect.intersects(dirtyRect) {
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2.5, yRadius: rect.height / 2.5).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(9, rect.height - 4), weight: .bold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let label = "⋯" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
    }

    /// The frames of a range of text, in view coordinates.
    func segmentFrames(of range: NSRange) -> [NSRect] {
        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else { return [] }
        var frames: [NSRect] = []
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            frames.append(frame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y))
            return true
        }
        return frames
    }

    /// The visual lines with an insertion point, across the whole width.
    private func currentLineRects() -> [NSRect] {
        let carets = editingRanges.filter { $0.length == 0 }
        guard carets.count == editingRanges.count else { return [] }
        return carets.compactMap { currentLineRect(at: $0.location) }
    }

    private func currentLineRect(at caret: Int) -> NSRect? {
        let selection = NSRange(location: caret, length: 0)
        guard let layoutManager = textLayoutManager,
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
        if !isSettingCursors {
            lastAddedOccurrence = nil
            if cursorRanges != nil {
                cursorRanges = nil
                updateCaretIndicators()
            }
        }
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
        guard indentation().usesSpaces, selectedRange().length == 0 else { return super.insertTab(sender) }
        let width = indentation().width
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
        guard indentation().usesSpaces, selectedRanges.count == 1, selection.length == 0, selection.location > 0 else {
            return super.deleteBackward(sender)
        }
        let text = string as NSString
        let lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let before = selection.location - lineStart
        guard before > 1, text.substring(with: NSRange(location: lineStart, length: before)).allSatisfy({ $0 == " " }) else {
            return super.deleteBackward(sender)
        }
        let width = indentation().width
        let count = before % width == 0 ? width : before % width
        let range = NSRange(location: selection.location - count, length: count)
        if shouldChangeText(in: range, replacementString: "") {
            textStorage?.replaceCharacters(in: range, with: "")
            didChangeText()
        }
    }

    /// Visual column of a location in its line, with tabs expanded.
    func column(at location: Int) -> Int {
        let text = string as NSString
        let lineStart = text.lineRange(for: NSRange(location: location, length: 0)).location
        let width = indentation().width
        var column = 0
        for index in lineStart..<location {
            column = text.character(at: index) == 0x09 ? (column / width + 1) * width : column + 1
        }
        return column
    }

    // MARK: - Comments and brackets

    /// ⌘/: comments the lines of the selection out, or in again if all of them are comments.
    /// Without a line comment in the language, the selection or line is wrapped in a block comment.
    @objc func toggleComment(_ sender: Any?) {
        guard let language = language() else { return NSSound.beep() }
        currentCommandTitle = String(localized: "Kommentar umschalten")
        defer { currentCommandTitle = nil }
        if let marker = language.lineComment {
            transformLines(scope: .selectionOrLine) { lines in
                let filled = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                let commented = !filled.isEmpty && filled.allSatisfy {
                    $0.drop { $0 == " " || $0 == "\t" }.hasPrefix(marker)
                }
                if commented {
                    return lines.map { line in
                        let indent = line.prefix { $0 == " " || $0 == "\t" }
                        var rest = line.dropFirst(indent.count)
                        guard rest.hasPrefix(marker) else { return line }
                        rest = rest.dropFirst(marker.count)
                        if rest.hasPrefix(" ") { rest = rest.dropFirst() }
                        return String(indent + rest)
                    }
                }
                // The marks go into one column, at the smallest indentation, as in Xcode.
                let column = filled.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
                return lines.map { line in
                    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
                    let index = line.index(line.startIndex, offsetBy: column)
                    return String(line[..<index]) + marker + " " + String(line[index...])
                }
            }
        } else if let (open, close) = language.blockComment {
            let text = string as NSString
            var range = selectedRange()
            if range.length == 0 {
                range = text.lineRange(for: range)
                while range.length > 0, text.character(at: range.upperBound - 1) == 0x0A { range.length -= 1 }
            }
            let selected = text.substring(with: range)
            let trimmed = selected.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(open) && trimmed.hasSuffix(close) && trimmed.count >= open.count + close.count {
                var inner = String(trimmed.dropFirst(open.count).dropLast(close.count))
                if inner.hasPrefix(" ") { inner.removeFirst() }
                if inner.hasSuffix(" ") { inner.removeLast() }
                let lead = selected.prefix { $0 == " " || $0 == "\t" }
                replace(range, with: lead + inner)
            } else {
                replace(range, with: open + " " + selected + " " + close)
            }
        }
    }

    /// Goes to the partner of the bracket next to the insertion point.
    @objc func jumpToMatchingBracket(_ sender: Any?) {
        let caret = selectedRange().location
        guard bracketRanges.count == 2 else { return NSSound.beep() }
        // The bracket touching the insertion point is the one to leave.
        let target = bracketRanges[0].location == caret || bracketRanges[0].upperBound == caret ? bracketRanges[1] : bracketRanges[0]
        let isOpening = language()?.brackets.contains { String($0.0) == (string as NSString).substring(with: target) } ?? false
        let location = isOpening ? target.location : target.upperBound
        setSelectedRange(NSRange(location: location, length: 0))
        scrollRangeToVisible(target)
        showFindIndicator(for: target)
    }

    /// The bracket before or after the insertion point and its partner, skipping nested pairs.
    func matchingBrackets(pairs: [(Character, Character)]) -> [NSRange] {
        let selection = selectedRange()
        guard selection.length == 0, !pairs.isEmpty else { return [] }
        let text = string as NSString
        let units = pairs.map { (open: $0.0.utf16.first!, close: $0.1.utf16.first!) }
        for location in [selection.location - 1, selection.location] where location >= 0 && location < text.length {
            let character = text.character(at: location)
            if let pair = units.first(where: { $0.open == character }) {
                var depth = 0
                var index = location + 1
                let limit = min(text.length, location + 100_000)
                while index < limit {
                    let current = text.character(at: index)
                    if current == pair.open { depth += 1 }
                    else if current == pair.close {
                        if depth == 0 { return [NSRange(location: location, length: 1), NSRange(location: index, length: 1)] }
                        depth -= 1
                    }
                    index += 1
                }
            } else if let pair = units.first(where: { $0.close == character }) {
                var depth = 0
                var index = location - 1
                let limit = max(0, location - 100_000)
                while index >= limit {
                    let current = text.character(at: index)
                    if current == pair.close { depth += 1 }
                    else if current == pair.open {
                        if depth == 0 { return [NSRange(location: index, length: 1), NSRange(location: location, length: 1)] }
                        depth -= 1
                    }
                    index -= 1
                }
            }
        }
        return []
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
