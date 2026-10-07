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

/// Short marks at the right edge of the text, one per line with a match, so the matches of the
/// whole document are visible at once. Positions follow line numbers, not the layout, which
/// TextKit only estimates for text not yet shown.
final class MatchMarksView: NSView {
    /// Positions from 0 (top) to 1 (bottom).
    var marks: [CGFloat] = [] { didSet { needsDisplay = true } }
    var current: CGFloat? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !marks.isEmpty else { return }
        let usable = bounds.height - 3
        NSColor.findHighlightColor.withAlphaComponent(0.9).setFill()
        var lastY: CGFloat = -10
        for mark in marks {
            let y = (mark * usable).rounded()
            guard y > lastY + 1 else { continue }
            lastY = y
            NSRect(x: 1, y: y, width: bounds.width - 2, height: 2).fill()
        }
        if let current {
            EditorStyle.insertionPointColor.setFill()
            NSRect(x: 0, y: (current * usable).rounded() - 1, width: bounds.width, height: 4).fill()
        }
    }
}

/// Searching, replacing and going to a line in one editor view. The bar sits above the text;
/// the matches are highlighted in the text and marked at the edge while it is open.
final class SearchController: FindBarDelegate {
    private unowned var textView: EditorTextView
    private unowned var layoutManager: NSTextLayoutManager
    private unowned let document: TextDocument
    let bar = FindBar()
    let marksView = MatchMarksView()

    private var matches: [NSTextCheckingResult] = []
    private var highlighted = false
    /// Where the typed search started; the first match from here is selected while typing.
    private var anchor = 0
    /// The selection searched in, while "only in the selection" is on; follows edits.
    private var scope: NSRange?
    private var pendingSearch: DispatchWorkItem?
    private var observer: NSObjectProtocol?

    init(textView: EditorTextView, layoutManager: NSTextLayoutManager, document: TextDocument) {
        self.textView = textView
        self.layoutManager = layoutManager
        self.document = document
        bar.delegate = self
        bar.isHidden = true
        observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: document.textStorage, queue: .main
        ) { [weak self] _ in
            self?.textDidChange()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Searches in another view of the document, after the focus moved to it in a split editor.
    func retarget(textView: EditorTextView, layoutManager: NSTextLayoutManager) {
        guard textView !== self.textView else { return }
        clearHighlights()
        self.textView = textView
        self.layoutManager = layoutManager
        if isVisible, bar.mode != .goToLine, !matches.isEmpty { highlightMatches() }
    }

    var isVisible: Bool { !bar.isHidden }
    /// The editor moves the text below the bar while it is shown.
    var onVisibilityChange: ((Bool) -> Void)?

    // MARK: - Opening and closing

    func show(_ mode: FindBar.Mode) {
        let wasVisible = isVisible
        bar.setMode(mode)
        if mode != .goToLine {
            let selection = textView.selectedRange()
            let text = textView.string as NSString
            if selection.length > 0, selection.length < 2000, textView.selectedRanges.count == 1, !bar.searchesInSelection {
                // The selection becomes the search term.
                let selected = text.substring(with: selection)
                bar.setSearchText(bar.isRegularExpression ? NSRegularExpression.escapedPattern(for: selected) : selected)
                Self.findPasteboardText = selected
            } else if bar.searchField.stringValue.isEmpty, let shared = Self.findPasteboardText {
                bar.setSearchText(bar.isRegularExpression ? NSRegularExpression.escapedPattern(for: shared) : shared)
            }
            anchor = selection.location
        } else {
            clearHighlights()
            bar.setStatus(String(localized: "Zeilen 1–\(document.lineIndex.lineCount.formatted())"))
        }
        bar.isHidden = false
        onVisibilityChange?(true)
        bar.focusSearchField()
        if mode != .goToLine {
            if !wasVisible || matches.isEmpty {
                // Opening highlights the matches; the selection stays until ↩ or typing.
                search(selectingFirst: false)
            } else {
                updateStatus()
            }
        }
    }

    func close() {
        guard isVisible else { return }
        if bar.mode != .goToLine { FindBar.remember(bar.searchField.stringValue) }
        bar.isHidden = true
        onVisibilityChange?(false)
        clearHighlights()
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: - Searching

    /// Searches again with the current query; while typing, the first match from the anchor
    /// is selected.
    private func search(selectingFirst: Bool) {
        pendingSearch?.cancel()
        pendingSearch = nil
        clearHighlights()
        let query = bar.query
        bar.setError(false)
        guard !query.isEmpty else {
            matches = []
            bar.setStatus("")
            bar.setPreview(nil)
            return
        }
        do {
            matches = try query.matches(in: textView.string, range: scope)
        } catch SearchQuery.Failure.invalidPattern(let message) {
            matches = []
            bar.setError(true)
            bar.setStatus(String(localized: "Ungültig"), isError: true, detail: message)
            bar.setPreview(nil)
            return
        } catch {
            matches = []
            return
        }
        highlightMatches()
        if selectingFirst, let match = match(from: anchor, backwards: false) {
            select(match, indicate: false)
        }
        updateStatus()
    }

    private func textDidChange() {
        guard document.textStorage.editedMask.contains(.editedCharacters) else { return }
        adjustScope()
        guard isVisible, bar.mode != .goToLine else { return }
        // Searching again after every keystroke is wasted work; after a pause it is enough.
        pendingSearch?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.search(selectingFirst: false) }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// The search runs over the query of the bar, even when it is closed (⌘G), then with the
    /// search text shared with other apps.
    private func ensureMatches() {
        if bar.searchField.stringValue.isEmpty, let shared = Self.findPasteboardText {
            bar.setSearchText(shared)
        }
        if !isVisible || pendingSearch != nil {
            let query = bar.query
            matches = (try? query.matches(in: textView.string, range: scope)) ?? []
            pendingSearch?.cancel()
            pendingSearch = nil
        }
    }

    func findNext(backwards: Bool) {
        ensureMatches()
        guard !matches.isEmpty else {
            NSSound.beep()
            if isVisible { updateStatus() }
            return
        }
        let selection = textView.selectedRange()
        let start = backwards ? selection.location : selection.upperBound
        var wrapped = false
        var match = self.match(from: start, backwards: backwards, strictly: true)
        if match == nil {
            wrapped = true
            match = backwards ? matches.last : matches.first
        }
        guard let match else { return }
        select(match, indicate: true)
        anchor = match.range.location
        FindBar.remember(bar.searchField.stringValue)
        Self.findPasteboardText = bar.query.regularExpression ? nil : bar.searchField.stringValue
        if isVisible {
            updateStatus()
            if wrapped {
                bar.setStatus(backwards ? String(localized: "Vom Ende") : String(localized: "Von vorn"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.updateStatus() }
            }
        }
    }

    /// Forward: the first match starting at or after the location. Backwards: the last match
    /// before it, entirely before it if `strictly`.
    private func match(from location: Int, backwards: Bool, strictly: Bool = false) -> NSTextCheckingResult? {
        if backwards {
            return matches.last { strictly ? $0.range.upperBound <= location : $0.range.location <= location }
        }
        return matches.first { $0.range.location >= location }
    }

    private func select(_ match: NSTextCheckingResult, indicate: Bool) {
        textView.setSelectedRange(match.range)
        textView.scrollRangeToVisible(match.range)
        if indicate { textView.showFindIndicator(for: match.range) }
        updateMarks()
        updatePreview()
    }

    private var currentIndex: Int? {
        let selection = textView.selectedRange()
        return matches.firstIndex { $0.range == selection }
    }

    private func updateStatus() {
        guard isVisible, bar.mode != .goToLine, !bar.query.isEmpty else { return }
        let count = matches.count
        if count == 0 {
            bar.setStatus(String(localized: "Keine Treffer"), isError: true)
        } else if let index = currentIndex {
            bar.setStatus(String(localized: "\((index + 1).formatted()) von \(count.formatted())"))
        } else {
            bar.setStatus(count == 1 ? String(localized: "1 Treffer") : String(localized: "\(count.formatted()) Treffer"))
        }
        updateMarks()
        updatePreview()
    }

    // MARK: - Highlighting

    private func highlightMatches() {
        guard let content = layoutManager.textContentManager else { return }
        let start = content.documentRange.location
        let color = NSColor.findHighlightColor.withAlphaComponent(0.45)
        for match in matches.prefix(20_000) {
            guard let from = content.location(start, offsetBy: match.range.location),
                  let to = content.location(from, offsetBy: match.range.length),
                  let range = NSTextRange(location: from, end: to)
            else { continue }
            layoutManager.addRenderingAttribute(.backgroundColor, value: color, for: range)
        }
        highlighted = true
        textView.redrawFragments()
        updateMarks()
    }

    private func clearHighlights() {
        if highlighted {
            layoutManager.removeRenderingAttribute(.backgroundColor, for: layoutManager.documentRange)
            highlighted = false
            textView.redrawFragments()
        }
        marksView.marks = []
        marksView.current = nil
    }

    private func updateMarks() {
        guard isVisible, highlighted else { return }
        let lines = max(document.lineIndex.lineCount - 1, 1)
        let lineIndex = document.lineIndex
        marksView.marks = matches.prefix(20_000).map { CGFloat(lineIndex.lineNumber(at: $0.range.location) - 1) / CGFloat(lines) }
        marksView.current = currentIndex.map { CGFloat(lineIndex.lineNumber(at: matches[$0].range.location) - 1) / CGFloat(lines) }
    }

    // MARK: - Replacing

    private func updatePreview() {
        guard isVisible, bar.mode == .replace, bar.isRegularExpression, let index = currentIndex,
              let replacement = try? bar.query.replacement(for: matches[index], in: textView.string, template: bar.replacementTemplate)
        else { return bar.setPreview(nil) }
        let visible = replacement.replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "\t", with: "⇥")
        bar.setPreview("„\(visible)“")
    }

    /// Replaces the selected match and goes to the next one; if the selection is no match,
    /// only goes to the next one.
    func replace() {
        ensureMatches()
        guard let index = currentIndex else { return findNext(backwards: false) }
        let match = matches[index]
        guard let replacement = try? bar.query.replacement(for: match, in: textView.string, template: bar.replacementTemplate),
              textView.shouldChangeText(in: match.range, replacementString: replacement)
        else { return NSSound.beep() }
        textView.textStorage?.replaceCharacters(in: match.range, with: replacement)
        textView.didChangeText()
        textView.undoManager?.setActionName(String(localized: "Ersetzen"))
        let after = match.range.location + (replacement as NSString).length
        textView.setSelectedRange(NSRange(location: after, length: 0))
        search(selectingFirst: false)
        findNext(backwards: false)
    }

    /// Replaces every match in one step, which one undo takes back.
    func replaceAll() {
        ensureMatches()
        guard !matches.isEmpty else { return NSSound.beep() }
        let string = textView.string
        let query = bar.query
        var ranges: [NSValue] = []
        var replacements: [String] = []
        for match in matches {
            guard let replacement = try? query.replacement(for: match, in: string, template: bar.replacementTemplate) else { continue }
            ranges.append(NSValue(range: match.range))
            replacements.append(replacement)
        }
        guard textView.shouldChangeText(inRanges: ranges, replacementStrings: replacements), let storage = textView.textStorage else {
            return NSSound.beep()
        }
        storage.beginEditing()
        for (range, replacement) in zip(ranges, replacements).reversed() {
            storage.replaceCharacters(in: range.rangeValue, with: replacement)
        }
        storage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName(String(localized: "Alle ersetzen"))
        let count = replacements.count
        search(selectingFirst: false)
        bar.setStatus(count == 1 ? String(localized: "1 ersetzt") : String(localized: "\(count.formatted()) ersetzt"))
    }

    /// Selects every match; typing at all of them follows with multiple insertion points.
    func selectAll() {
        ensureMatches()
        guard !matches.isEmpty else { return NSSound.beep() }
        textView.selectedRanges = matches.map { NSValue(range: $0.range) }
        close()
    }

    // MARK: - Scope

    private func adjustScope() {
        guard var range = scope else { return }
        let storage = document.textStorage
        let edited = storage.editedRange
        let delta = storage.changeInLength
        let oldEnd = edited.upperBound - delta
        if oldEnd <= range.location {
            range.location += delta
        } else if edited.location < range.upperBound {
            range.length = max(0, range.length + delta)
        }
        scope = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
    }

    // MARK: - Going to a line

    /// Goes to "120", "120:15" (line and column), "+10" or "-10" (relative to the current line).
    func goTo(_ input: String) {
        let parts = input.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        let lineIndex = document.lineIndex
        let currentLine = lineIndex.lineNumber(at: textView.selectedRange().location)
        guard let first = parts.first.map(String.init), !first.isEmpty || parts.count > 1 else { return bar.setError(true) }
        var line = currentLine
        if first.hasPrefix("+"), let offset = Int(first.dropFirst()) {
            line = currentLine + offset
        } else if first.hasPrefix("-"), let offset = Int(first.dropFirst()) {
            line = currentLine - offset
        } else if let number = Int(first) {
            line = number
        } else if !first.isEmpty {
            return bar.setError(true)
        }
        line = line.clamped(to: 1...lineIndex.lineCount)
        var column = 1
        if parts.count > 1 {
            guard let number = Int(parts[1]) else { return bar.setError(true) }
            column = max(number, 1)
        }
        let text = textView.string as NSString
        let start = lineIndex.start(ofLine: line)
        let lineEnd = line < lineIndex.lineCount ? lineIndex.start(ofLine: line + 1) - 1 : text.length
        let location = min(start + column - 1, lineEnd)
        close()
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        textView.centerSelectionInVisibleArea(nil)
        textView.showFindIndicator(for: text.lineRange(for: NSRange(location: location, length: 0)))
    }

    // MARK: - FindBarDelegate

    func findBarQueryDidChange(_ bar: FindBar) { search(selectingFirst: true) }
    func findBar(_ bar: FindBar, findNextBackwards backwards: Bool) { findNext(backwards: backwards) }
    func findBarReplace(_ bar: FindBar) { replace() }
    func findBarReplaceAll(_ bar: FindBar) { replaceAll() }
    func findBarReplacementDidChange(_ bar: FindBar) { updatePreview() }
    func findBar(_ bar: FindBar, goTo input: String) { goTo(input) }
    func findBarClose(_ bar: FindBar) { close() }

    func findBarScopeDidChange(_ bar: FindBar) {
        let selection = textView.selectedRange()
        if bar.searchesInSelection {
            guard selection.length > 0 else {
                bar.searchesInSelection = false
                bar.setStatus(String(localized: "Keine Auswahl"), isError: true)
                return
            }
            scope = selection
        } else {
            scope = nil
        }
        search(selectingFirst: false)
    }

    /// Takes the selection as search term without opening the bar (⌘E).
    func useSelection() {
        let selection = textView.selectedRange()
        guard selection.length > 0 else { return NSSound.beep() }
        let selected = (textView.string as NSString).substring(with: selection)
        Self.findPasteboardText = selected
        bar.setSearchText(bar.isRegularExpression ? NSRegularExpression.escapedPattern(for: selected) : selected)
        if isVisible { search(selectingFirst: false) } else { matches = [] }
    }

    // MARK: - Find pasteboard

    /// The search text shared with other apps and with the other windows, as on every Mac.
    static var findPasteboardText: String? {
        get {
            let text = NSPasteboard(name: .find).string(forType: .string)
            return text?.isEmpty == false ? text : nil
        }
        set {
            guard let newValue, !newValue.isEmpty else { return }
            let pasteboard = NSPasteboard(name: .find)
            pasteboard.clearContents()
            pasteboard.setString(newValue, forType: .string)
        }
    }
}
