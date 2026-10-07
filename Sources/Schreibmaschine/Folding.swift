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

/// Code folding: the lines of a block are hidden, their first line stays visible with a mark.
///
/// A block is what is indented deeper than the line before it; where nothing is indented, a
/// bracket at the end of the line opens one that ends at its partner. Folds belong to the
/// document, so every view of it shows the same. TextKit 2 leaves the hidden lines out because
/// the content storage's delegate does not hand them out (`shouldEnumerate`).
enum FoldRegions {
    /// The lines a fold with this line as its head would hide, or nil if it heads no block.
    static func region(headedBy line: Int, in text: NSString, lineIndex: LineIndex, tabWidth: Int) -> ClosedRange<Int>? {
        let count = lineIndex.lineCount
        guard line < count, let headIndent = indent(ofLine: line, in: text, lineIndex: lineIndex, tabWidth: tabWidth) else { return nil }

        // Deeper indented lines below, blank lines within the block included.
        var last = line
        var next = line + 1
        while next <= count {
            if let indent = indent(ofLine: next, in: text, lineIndex: lineIndex, tabWidth: tabWidth) {
                if indent <= headIndent { break }
                last = next
            }
            next += 1
        }
        if last > line { return (line + 1)...last }

        // A bracket at the end of the line and its partner on a later line.
        let range = lineRange(line, in: text, lineIndex: lineIndex)
        var end = range.upperBound
        while end > range.location, [0x20, 0x09].contains(text.character(at: end - 1)) { end -= 1 }
        guard end > range.location else { return nil }
        let pairs: [unichar: unichar] = [0x7B: 0x7D, 0x5B: 0x5D, 0x28: 0x29]
        let opener = text.character(at: end - 1)
        guard let closer = pairs[opener] else { return nil }
        var depth = 0
        var index = end
        let limit = min(text.length, end + 500_000)
        while index < limit {
            let character = text.character(at: index)
            if character == opener { depth += 1 }
            else if character == closer {
                if depth == 0 {
                    let closingLine = lineIndex.lineNumber(at: index)
                    return closingLine - 1 > line ? (line + 1)...(closingLine - 1) : nil
                }
                depth -= 1
            }
            index += 1
        }
        return nil
    }

    /// Whether the line heads a block; cheaper than the region, for the marks in the ruler.
    static func isHead(_ line: Int, in text: NSString, lineIndex: LineIndex, tabWidth: Int) -> Bool {
        guard line < lineIndex.lineCount, let headIndent = indent(ofLine: line, in: text, lineIndex: lineIndex, tabWidth: tabWidth) else { return false }
        var next = line + 1
        while next <= lineIndex.lineCount, next <= line + 50 {
            if let indent = indent(ofLine: next, in: text, lineIndex: lineIndex, tabWidth: tabWidth) {
                if indent > headIndent { return true }
                break
            }
            next += 1
        }
        return region(headedBy: line, in: text, lineIndex: lineIndex, tabWidth: tabWidth) != nil
    }

    /// The width of the line's indentation, tabs expanded; nil for a blank line.
    static func indent(ofLine line: Int, in text: NSString, lineIndex: LineIndex, tabWidth: Int) -> Int? {
        let range = lineRange(line, in: text, lineIndex: lineIndex)
        var width = 0
        var index = range.location
        while index < range.upperBound {
            switch text.character(at: index) {
            case 0x20: width += 1
            case 0x09: width = (width / tabWidth + 1) * tabWidth
            default: return width
            }
            index += 1
        }
        return nil
    }

    /// The line without its line break.
    static func lineRange(_ line: Int, in text: NSString, lineIndex: LineIndex) -> NSRange {
        let start = lineIndex.start(ofLine: line)
        let end = line < lineIndex.lineCount ? lineIndex.start(ofLine: line + 1) - 1 : text.length
        return NSRange(location: start, length: max(end - start, 0))
    }
}

extension TextDocument: NSTextContentStorageDelegate {
    /// The characters of a region of lines, from the start of the first to the start of the line after the last.
    func characterRange(ofLines lines: ClosedRange<Int>) -> NSRange {
        let start = lineIndex.start(ofLine: lines.lowerBound)
        let end = lines.upperBound < lineIndex.lineCount ? lineIndex.start(ofLine: lines.upperBound + 1) : textStorage.length
        return NSRange(location: start, length: end - start)
    }

    /// The lines heading a fold.
    var foldedHeads: [Int] { folds.map { lineIndex.lineNumber(at: $0.location) - 1 } }

    func foldRegion(headedBy line: Int) -> ClosedRange<Int>? {
        FoldRegions.region(headedBy: line, in: textStorage.string as NSString, lineIndex: lineIndex, tabWidth: indentation.width)
    }

    func isFoldHead(_ line: Int) -> Bool {
        FoldRegions.isHead(line, in: textStorage.string as NSString, lineIndex: lineIndex, tabWidth: indentation.width)
    }

    /// Folds the block headed by the line. Folds inside it are kept and come back when it is unfolded.
    @discardableResult
    func fold(headedBy line: Int) -> Bool {
        guard let region = foldRegion(headedBy: line) else { return false }
        let range = characterRange(ofLines: region)
        guard !folds.contains(where: { NSEqualRanges($0, range) }) else { return false }
        setFolds(folds + [range])
        return true
    }

    func unfold(headedBy line: Int) {
        setFolds(folds.filter { lineIndex.lineNumber(at: $0.location) - 1 != line })
    }

    /// Unfolds everything that hides the location.
    func unfold(containing location: Int) {
        let remaining = folds.filter { !($0.location <= location && location < $0.upperBound) }
        if remaining.count != folds.count { setFolds(remaining) }
    }

    func setFoldedHeads(_ heads: [Int]) {
        setFolds(heads.compactMap { foldRegion(headedBy: $0).map(characterRange(ofLines:)) })
    }

    func setFolds(_ ranges: [NSRange]) {
        folds = ranges.sorted { $0.location < $1.location }
        NotificationCenter.default.post(name: Self.foldsDidChange, object: self)
        SessionStore.shared.setNeedsSave()
    }

    /// Whether the location is hidden by a fold.
    func isFolded(_ location: Int) -> Bool {
        folds.contains { $0.location <= location && location < $0.upperBound }
    }

    /// A fold touched by an edit opens; the others move with the text.
    func adjustFolds() {
        guard !folds.isEmpty else { return }
        let edited = textStorage.editedRange
        let delta = textStorage.changeInLength
        let oldEnd = edited.upperBound - delta
        let adjusted = folds.compactMap { fold -> NSRange? in
            // Before the line break that ends the head line: the fold moves.
            if oldEnd < fold.location { return NSRange(location: fold.location + delta, length: fold.length) }
            if edited.location >= fold.upperBound { return fold }
            return nil
        }
        if adjusted != folds {
            folds = adjusted
            NotificationCenter.default.post(name: Self.foldsDidChange, object: self)
        }
    }

    // MARK: NSTextContentStorageDelegate

    func textContentManager(_ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement,
                            options: NSTextContentManager.EnumerationOptions) -> Bool {
        guard !folds.isEmpty, let range = textElement.elementRange else { return true }
        let offset = textContentManager.offset(from: textContentManager.documentRange.location, to: range.location)
        return !isFolded(offset)
    }
}
