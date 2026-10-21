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

/// Several insertion points and selections at once: ⌘-click adds one, ⌥-drag selects a block
/// with one per line, ⌃G adds the next occurrence of the selection. Typing, deleting, moving
/// and pasting act at all of them; Esc or a plain click goes back to one.
///
/// NSTextView keeps several selections, but drops empty ones as soon as there is more than one,
/// and types only at the first. So the editor keeps the list itself (`cursorRanges`), gives
/// NSTextView the non-empty ranges to draw, and draws the other insertion points as
/// NSTextInsertionIndicator views.
extension EditorTextView {
    /// The ranges edited together: the own list, or NSTextView's selections if there are several.
    var editingRanges: [NSRange] {
        if let cursorRanges { return cursorRanges }
        return selectedRanges.map(\.rangeValue)
    }

    var hasMultipleCursors: Bool { editingRanges.count > 1 }

    /// Sets the ranges edited together, sorted and with overlapping ones merged.
    func setCursorRanges(_ ranges: [NSRange], primary: NSRange? = nil) {
        let merged = Self.merge(ranges)
        guard merged.count > 1 else {
            cursorRanges = nil
            updateCaretIndicators()
            setSelectedRange(merged.first ?? NSRange(location: 0, length: 0))
            return
        }
        cursorRanges = merged
        let selected = merged.filter { $0.length > 0 }
        let shown = selected.isEmpty ? [primary.flatMap { p in merged.first { $0.location == p.location } } ?? merged[0]] : selected
        isSettingCursors = true
        super.setSelectedRanges(shown.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
        isSettingCursors = false
        updateCaretIndicators()
        setNeedsDisplay(visibleRect)
    }

    /// Back to one insertion point or selection.
    func collapseCursors(to range: NSRange? = nil) {
        guard let range = range ?? editingRanges.first else { return }
        cursorRanges = nil
        updateCaretIndicators()
        setSelectedRange(range)
    }

    static func merge(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location || ($0.location == $1.location && $0.length < $1.length) }) {
            if let last = result.last, range.location < last.upperBound || (range.location == last.location) || (range.length == 0 && range.location == last.upperBound && last.length > 0) {
                result[result.count - 1] = NSUnionRange(last, range)
            } else {
                result.append(range)
            }
        }
        return result
    }

    // MARK: - Drawing the insertion points

    func updateCaretIndicators() {
        let shown = selectedRanges.map(\.rangeValue)
        let carets = (cursorRanges ?? []).filter { $0.length == 0 && !(shown.count == 1 && shown[0] == $0) }
        while caretIndicators.count > carets.count { caretIndicators.removeLast().removeFromSuperview() }
        while caretIndicators.count < carets.count {
            let indicator = NSTextInsertionIndicator(frame: .zero)
            indicator.color = insertionPointColor
            addSubview(indicator)
            caretIndicators.append(indicator)
        }
        let active = window?.isKeyWindow == true && window?.firstResponder === self
        for (indicator, caret) in zip(caretIndicators, carets) {
            indicator.frame = caretRect(at: caret.location)
            indicator.displayMode = active ? .automatic : .hidden
        }
    }

    func caretRect(at location: Int) -> NSRect {
        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager,
              let textLocation = content.location(content.documentRange.location, offsetBy: location)
        else { return .zero }
        var rect = NSRect.zero
        layoutManager.enumerateTextSegments(in: NSTextRange(location: textLocation), type: .selection, options: [.rangeNotRequired]) { _, frame, _, _ in
            rect = frame
            return false
        }
        return NSRect(x: rect.minX + textContainerOrigin.x - 0.5, y: rect.minY + textContainerOrigin.y, width: 2, height: rect.height)
    }

    // MARK: - Editing at all insertion points

    /// Replaces every range with its text in one undo step; afterwards the insertion points
    /// stand behind the new texts, or the texts are selected.
    func replaceRanges(_ ranges: [NSRange], with texts: [String], selectingInserted: Bool = false) {
        guard ranges.count == texts.count, !ranges.isEmpty,
              shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: texts),
              let storage = textStorage
        else { return }
        let order = ranges.indices.sorted { ranges[$0].location > ranges[$1].location }
        isSettingCursors = true
        for index in order {
            storage.replaceCharacters(in: ranges[index], with: texts[index])
        }
        isSettingCursors = false
        didChangeText()
        var shift = 0
        var result: [NSRange] = []
        for index in ranges.indices.sorted(by: { ranges[$0].location < ranges[$1].location }) {
            let length = (texts[index] as NSString).length
            let start = ranges[index].location + shift
            result.append(selectingInserted ? NSRange(location: start, length: length) : NSRange(location: start + length, length: 0))
            shift += length - ranges[index].length
        }
        setCursorRanges(result)
        scrollRangeToVisible(result.last!)
    }

    /// For an insertion point, the range a movement or deletion command would select from it.
    private func rangeByPerforming(_ selector: Selector, from range: NSRange) -> NSRange {
        isSettingCursors = true
        super.setSelectedRanges([NSValue(range: range)], affinity: .downstream, stillSelecting: false)
        _ = perform(selector, with: nil)
        let result = selectedRange()
        isSettingCursors = false
        return result
    }

    private static let deletions: [Selector: Selector] = [
        #selector(deleteBackward(_:)): #selector(moveBackwardAndModifySelection(_:)),
        #selector(deleteForward(_:)): #selector(moveForwardAndModifySelection(_:)),
        #selector(deleteWordBackward(_:)): #selector(moveWordBackwardAndModifySelection(_:)),
        #selector(deleteWordForward(_:)): #selector(moveWordForwardAndModifySelection(_:)),
        #selector(deleteToBeginningOfLine(_:)): #selector(moveToBeginningOfLineAndModifySelection(_:)),
        #selector(deleteToEndOfLine(_:)): #selector(moveToEndOfLineAndModifySelection(_:)),
        #selector(deleteToBeginningOfParagraph(_:)): #selector(moveToBeginningOfParagraphAndModifySelection(_:)),
        #selector(deleteToEndOfParagraph(_:)): #selector(moveToEndOfParagraphAndModifySelection(_:)),
        #selector(deleteBackwardByDecomposingPreviousCharacter(_:)): #selector(moveBackwardAndModifySelection(_:)),
    ]

    /// Moves that make no sense at several places end the multiple insertion points.
    private static let collapsingMoves: Set<String> = [
        "moveToBeginningOfDocument:", "moveToEndOfDocument:", "moveToBeginningOfDocumentAndModifySelection:",
        "moveToEndOfDocumentAndModifySelection:", "pageUp:", "pageDown:", "pageUpAndModifySelection:",
        "pageDownAndModifySelection:", "scrollPageUp:", "scrollPageDown:",
        "movePageUp:", "movePageDown:", "movePageUpAndModifySelection:", "movePageDownAndModifySelection:",
    ]

    /// Key commands at several insertion points. Returns false for the ones NSTextView handles.
    func performMultiCursorCommand(_ selector: Selector) -> Bool {
        guard hasMultipleCursors else { return false }
        let ranges = editingRanges
        let name = NSStringFromSelector(selector)

        if let move = Self.deletions[selector] {
            guard isEditable else { return true }
            let targets = ranges.map { $0.length > 0 ? $0 : rangeByPerforming(move, from: $0) }
            replaceRanges(Self.merge(targets), with: Self.merge(targets).map { _ in "" })
            return true
        }
        if name.hasPrefix("move") && !Self.collapsingMoves.contains(name) {
            let moved = ranges.map { rangeByPerforming(selector, from: $0) }
            setCursorRanges(moved)
            if let last = moved.last { scrollRangeToVisible(last) }
            return true
        }
        switch selector {
        case #selector(insertNewline(_:)):
            let text = string as NSString
            replaceRanges(ranges, with: ranges.map { range in
                guard Preferences.autoIndentsValue else { return "\n" }
                let lineStart = text.lineRange(for: NSRange(location: range.location, length: 0)).location
                var end = lineStart
                while end < range.location, [0x20, 0x09].contains(text.character(at: end)) { end += 1 }
                return "\n" + text.substring(with: NSRange(location: lineStart, length: end - lineStart))
            })
            return true
        case #selector(insertTab(_:)):
            let unit = indentation()
            replaceRanges(ranges, with: ranges.map { range in
                guard unit.usesSpaces else { return "\t" }
                return String(repeating: " ", count: unit.width - column(at: range.location) % unit.width)
            })
            return true
        default:
            if Self.collapsingMoves.contains(name) { collapseCursors() }
            return false
        }
    }

    // MARK: - Clipboard

    /// Copies the selected texts, one per line.
    func copyMultiple(to pasteboard: NSPasteboard) -> Bool {
        let selected = editingRanges.filter { $0.length > 0 }
        guard hasMultipleCursors, !selected.isEmpty else { return false }
        let text = string as NSString
        pasteboard.clearContents()
        pasteboard.setString(selected.map { text.substring(with: $0) }.joined(separator: "\n"), forType: .string)
        return true
    }

    /// With as many lines on the clipboard as insertion points, each gets its own line.
    func pasteMultiple(from pasteboard: NSPasteboard) -> Bool {
        guard hasMultipleCursors, let text = pasteboard.string(forType: .string)?.normalizingLineEndings else { return false }
        let ranges = editingRanges
        var lines = text.components(separatedBy: "\n")
        if lines.count == ranges.count + 1, lines.last == "" { lines.removeLast() }
        replaceRanges(ranges, with: lines.count == ranges.count ? lines : ranges.map { _ in text })
        return true
    }

    // MARK: - Mouse

    /// ⌘-click adds an insertion point, or removes one; ⌘-drag adds a selection.
    func addCursor(with event: NSEvent) {
        let start = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        var ranges = editingRanges
        if let hit = ranges.firstIndex(where: { $0.length == 0 ? $0.location == start : NSLocationInRange(start, $0) }), ranges.count > 1 {
            // Clicking an insertion point or selection again removes it.
            if event.clickCount == 1, nextDragOrUp() == .leftMouseUp {
                ranges.remove(at: hit)
                setCursorRanges(ranges)
                return
            }
        }
        var current = NSRange(location: start, length: 0)
        trackMouse { point in
            let index = self.characterIndexForInsertion(at: point)
            current = NSRange(location: min(start, index), length: abs(index - start))
            self.setCursorRanges(ranges + [current], primary: current)
        }
        setCursorRanges(ranges + [current], primary: current)
    }

    /// ⌥-drag selects a block: the same columns in every line between start and end, with an
    /// insertion point in each line if the block has no width.
    func selectBlock(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        func update(to end: NSPoint) {
            let ranges = blockRanges(from: start, to: end)
            if !ranges.isEmpty { setCursorRanges(ranges, primary: ranges.last) }
        }
        update(to: start)
        trackMouse(update)
    }

    private func blockRanges(from start: NSPoint, to end: NSPoint) -> [NSRange] {
        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager else { return [] }
        let top = min(start.y, end.y), bottom = max(start.y, end.y)
        let left = min(start.x, end.x), right = max(start.x, end.x)
        let origin = textContainerOrigin
        var ranges: [NSRange] = []
        let topPoint = CGPoint(x: 0, y: max(0, top - origin.y))
        let first = layoutManager.textLayoutFragment(for: topPoint)?.rangeInElement.location ?? content.documentRange.location
        layoutManager.enumerateTextLayoutFragments(from: first, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY + origin.y > bottom { return false }
            for line in fragment.textLineFragments {
                let y = frame.minY + line.typographicBounds.midY + origin.y
                let lineTop = frame.minY + line.typographicBounds.minY + origin.y
                let lineBottom = frame.minY + line.typographicBounds.maxY + origin.y
                guard lineBottom >= top, lineTop <= bottom else { continue }
                let from = characterIndexForInsertion(at: NSPoint(x: left, y: y))
                let to = characterIndexForInsertion(at: NSPoint(x: right, y: y))
                ranges.append(NSRange(location: min(from, to), length: abs(to - from)))
            }
            return true
        }
        return ranges
    }

    /// Follows the mouse until it is released, scrolling at the edges.
    private func trackMouse(_ handler: (NSPoint) -> Void) {
        guard let window else { return }
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp { break }
            autoscroll(with: event)
            handler(convert(event.locationInWindow, from: nil))
        }
    }

    /// Whether the mouse is released before it moves, without taking the event from the queue.
    private func nextDragOrUp() -> NSEvent.EventType? {
        window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: false)?.type
    }

    // MARK: - ⌃G

    /// Selects the word at the insertion point, or adds the next occurrence of the selected text.
    @objc func selectNextOccurrence(_ sender: Any?) {
        let text = string as NSString
        var ranges = editingRanges
        guard let last = ranges.last else { return }
        if ranges.count == 1, last.length == 0 {
            let word = selectionRange(forProposedRange: NSRange(location: last.location, length: 0), granularity: .selectByWord)
            guard word.length > 0 else { return NSSound.beep() }
            setSelectedRange(word)
            return
        }
        guard let pattern = ranges.first(where: { $0.length > 0 }).map({ text.substring(with: $0) }) else { return NSSound.beep() }
        let newest = lastAddedOccurrence ?? last
        var found = text.range(of: pattern, options: [.literal], range: NSRange(location: newest.upperBound, length: text.length - newest.upperBound))
        if found.location == NSNotFound {
            found = text.range(of: pattern, options: [.literal], range: NSRange(location: 0, length: newest.location))
        }
        guard found.location != NSNotFound, !ranges.contains(found) else { return NSSound.beep() }
        ranges.append(found)
        setCursorRanges(ranges)
        lastAddedOccurrence = found
        scrollRangeToVisible(found)
        showFindIndicator(for: found)
    }

    /// One insertion point at the end of each line of the selection.
    @objc func splitSelectionIntoLines(_ sender: Any?) {
        let text = string as NSString
        var ranges: [NSRange] = []
        for selection in editingRanges {
            guard selection.length > 0 else { ranges.append(selection); continue }
            var location = selection.location
            while location < selection.upperBound {
                let line = text.lineRange(for: NSRange(location: location, length: 0))
                var end = min(line.upperBound, selection.upperBound)
                if end > location, end == line.upperBound, text.character(at: end - 1) == 0x0A { end -= 1 }
                ranges.append(NSRange(location: end, length: 0))
                location = line.upperBound
            }
        }
        guard ranges.count > 1 else { return NSSound.beep() }
        setCursorRanges(ranges)
    }
}
