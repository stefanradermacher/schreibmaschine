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

/// Help for writing Markdown: lists and quotes go on after ↩, ⇥ indents a list item, and bold,
/// italic, and links are put around the selection or taken away again.
extension EditorTextView {
    var isMarkdown: Bool { language()?.id == "markdown" }

    // MARK: - Lists and quotes

    /// The start of a list item or quoted line: indentation, quote marks, and the list mark with
    /// its number and task box.
    private static let listPrefix = try! NSRegularExpression(
        pattern: #"^([ \t]*)((?:>[ \t]?)*)(?:([ \t]*)(?:([-*+])|(\d+)([.)]))([ \t]+)(\[[ xX]\][ \t]+)?)?"#)

    /// ↩ in a list item starts the next item; in an empty one it ends the list. The same for
    /// quoted lines. Returns false if the line is neither.
    func continueMarkdownList() -> Bool {
        guard isMarkdown, !hasMultipleCursors else { return false }
        let text = string as NSString
        let selection = selectedRange()
        let line = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let head = NSRange(location: line.location, length: selection.location - line.location)
        guard let match = Self.listPrefix.firstMatch(in: string, range: head), match.range.length > 0 else { return false }
        func part(_ index: Int) -> String {
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : text.substring(with: range)
        }
        let quote = part(2), bullet = part(4), number = part(5)
        guard !quote.isEmpty || !bullet.isEmpty || !number.isEmpty else { return false }
        // Only the prefix up to the insertion point counts; ↩ inside it is an ordinary line break.
        guard match.range.upperBound <= selection.location else { return false }
        var contentsEnd = 0
        text.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: line)
        let rest = text.substring(with: NSRange(location: match.range.upperBound, length: contentsEnd - match.range.upperBound))
        if rest.trimmingCharacters(in: .whitespaces).isEmpty, selection.length == 0 {
            // An empty item ends the list: the mark goes, a quote around the list stays. An empty
            // quoted line ends the quote.
            let keep = bullet.isEmpty && number.isEmpty ? "" : quote
            insertText(keep, replacementRange: NSRange(location: line.location, length: contentsEnd - line.location))
            return true
        }
        var next = part(1) + quote + part(3)
        if !bullet.isEmpty {
            next += bullet + part(7)
        } else if let value = Int(number) {
            next += String(value + 1) + part(6) + part(7)
        }
        if match.range(at: 8).location != NSNotFound { next += "[ ] " }
        insertText("\n" + next, replacementRange: selection)
        return true
    }

    /// ⇥ anywhere in a list item indents the whole item, as in other Markdown editors.
    func indentMarkdownListItem() -> Bool {
        guard isMarkdown, !hasMultipleCursors, selectedRange().length == 0 else { return false }
        let text = string as NSString
        let line = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        guard let match = Self.listPrefix.firstMatch(in: string, range: line),
              match.range(at: 4).location != NSNotFound || match.range(at: 5).location != NSNotFound
        else { return false }
        // The insertion point stays where it was in the text of the item.
        let fromEnd = NSMaxRange(line) - selectedRange().location
        currentCommandTitle = String(localized: "Einrücken")
        indentLines()
        currentCommandTitle = nil
        let indented = (string as NSString).lineRange(for: NSRange(location: line.location, length: 0))
        setSelectedRange(NSRange(location: NSMaxRange(indented) - fromEnd, length: 0))
        return true
    }

    // MARK: - Bold, italic, links

    /// Puts the mark around the selection, or around the word at the insertion point; if it is
    /// there already, takes it away. Without a word, inserts the marks with the insertion point
    /// between them.
    func toggleMarkdownMark(_ mark: String) {
        let text = string as NSString
        var range = selectedRange()
        if range.length == 0 { range = wordRange(at: range.location) ?? range }
        let length = (mark as NSString).length
        let inner = text.substring(with: range)
        // The marks are part of the selection.
        if range.length >= 2 * length, inner.hasPrefix(mark), inner.hasSuffix(mark) {
            let stripped = String(inner.dropFirst(mark.count).dropLast(mark.count))
            insertText(stripped, replacementRange: range)
            setSelectedRange(NSRange(location: range.location, length: (stripped as NSString).length))
            return
        }
        // The marks are around the selection.
        if range.location >= length, range.upperBound + length <= text.length,
           text.substring(with: NSRange(location: range.location - length, length: length)) == mark,
           text.substring(with: NSRange(location: range.upperBound, length: length)) == mark {
            let outer = NSRange(location: range.location - length, length: range.length + 2 * length)
            insertText(inner, replacementRange: outer)
            setSelectedRange(NSRange(location: outer.location, length: range.length))
            return
        }
        insertText(mark + inner + mark, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + length, length: range.length))
    }

    /// Makes the selection the text of a link and selects the place for the address; a selected
    /// address becomes the address, with the insertion point in the brackets for the text.
    func insertMarkdownLink() {
        let text = string as NSString
        var range = selectedRange()
        if range.length == 0 { range = wordRange(at: range.location) ?? range }
        let inner = text.substring(with: range)
        if inner.hasPrefix("http://") || inner.hasPrefix("https://") || inner.hasPrefix("mailto:") {
            insertText("[](" + inner + ")", replacementRange: range)
            setSelectedRange(NSRange(location: range.location + 1, length: 0))
            return
        }
        let placeholder = "https://"
        insertText("[" + inner + "](" + placeholder + ")", replacementRange: range)
        setSelectedRange(NSRange(location: range.location + (inner as NSString).length + 3, length: (placeholder as NSString).length))
    }

    /// The word the insertion point is in or next to, if any.
    private func wordRange(at location: Int) -> NSRange? {
        let text = string as NSString
        func isWord(_ index: Int) -> Bool {
            guard index >= 0, index < text.length, let scalar = Unicode.Scalar(text.character(at: index)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }
        var start = location, end = location
        while isWord(start - 1) { start -= 1 }
        while isWord(end) { end += 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }
}
