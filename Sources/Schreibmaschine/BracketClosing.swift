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

/// Brackets and quotation marks close themselves: typing an opening one adds its partner, typing
/// the partner then steps over it, and ⌫ between an empty pair removes both. With a selection,
/// they go around it. Works at every insertion point.
extension EditorTextView {
    private struct Pairing {
        let brackets: [Character: Character]
        let closers: Set<Character>
        let quotes: Set<Character>
        /// Marks that only go around a selection, such as * and _ in Markdown.
        let wrappers: Set<Character>
    }

    private var pairing: Pairing {
        let pairs = language()?.brackets ?? [("(", ")"), ("[", "]"), ("{", "}")]
        return Pairing(
            brackets: Dictionary(pairs, uniquingKeysWith: { first, _ in first }),
            closers: Set(pairs.map(\.1)),
            // Plain text is prose: only " closes itself, an apostrophe never.
            quotes: Set(language()?.quotes ?? ["\""]),
            wrappers: isMarkdown ? ["*", "_", "~"] : [])
    }

    /// Typed text at every insertion point, with pairs closed. Returns false if no pair was
    /// involved; the text is then inserted as usual.
    func insertClosingPairs(_ typed: String) -> Bool {
        guard Preferences.closesBracketsValue, !hasMarkedText(), typed.count == 1, let character = typed.first else { return false }
        let pairing = pairing
        guard pairing.brackets[character] != nil || pairing.closers.contains(character)
                || pairing.quotes.contains(character) || pairing.wrappers.contains(character)
        else { return false }
        let text = string as NSString
        let ranges = editingRanges
        var edits: [(range: NSRange, text: String, selection: NSRange)] = []
        var paired = false
        for range in ranges {
            let edit = self.edit(typing: character, typed: typed, at: range, in: text, pairing: pairing)
            if edit.paired { paired = true }
            edits.append((edit.range, edit.text, edit.selection))
        }
        guard paired else { return false }
        replaceRanges(edits.map(\.range), with: edits.map(\.text))
        // The insertion points as each edit wants them, shifted by the edits before.
        var shift = 0
        var selections: [NSRange] = []
        for edit in edits.sorted(by: { $0.range.location < $1.range.location }) {
            selections.append(NSRange(location: edit.range.location + shift + edit.selection.location, length: edit.selection.length))
            shift += (edit.text as NSString).length - edit.range.length
        }
        setCursorRanges(selections)
        return true
    }

    /// What typing a character does at one range: the range to replace, the text, and the
    /// selection afterwards, relative to the start of the range.
    private func edit(typing character: Character, typed: String, at range: NSRange, in text: NSString,
                      pairing: Pairing) -> (range: NSRange, text: String, selection: NSRange, paired: Bool) {
        let length = (typed as NSString).length
        let plain = (range, typed, NSRange(location: length, length: 0), false)
        func char(at index: Int) -> Character? {
            guard index >= 0, index < text.length else { return nil }
            return Character(text.substring(with: text.rangeOfComposedCharacterSequence(at: index)))
        }
        let closer = pairing.brackets[character] ?? (pairing.quotes.contains(character) || pairing.wrappers.contains(character) ? character : nil)

        // Around a selection.
        if range.length > 0 {
            guard let closer else { return plain }
            let inner = text.substring(with: range)
            return (range, typed + inner + String(closer), NSRange(location: length, length: range.length), true)
        }
        let next = char(at: range.location)
        // Over the partner that is already there.
        if next == character, pairing.closers.contains(character) || pairing.quotes.contains(character) {
            return (NSRange(location: range.location, length: (String(character) as NSString).length), typed,
                    NSRange(location: length, length: 0), true)
        }
        guard let closer, !pairing.wrappers.contains(character) || pairing.quotes.contains(character) else { return plain }
        // Only before space, the end of the line, a closing bracket, or punctuation; before a
        // word the partner would be in the way.
        if let next, !(next.isWhitespace || pairing.closers.contains(next) || ",;:.".contains(next)) { return plain }
        if pairing.quotes.contains(character), let previous = char(at: range.location - 1),
           previous.isLetter || previous.isNumber || previous == character {
            // An apostrophe in a word, or a quote that ends one.
            return plain
        }
        return (range, typed + String(closer), NSRange(location: length, length: 0), true)
    }

    /// ⌫ between an empty pair removes both. Returns false otherwise.
    func deleteClosingPair() -> Bool {
        guard Preferences.closesBracketsValue, !hasMultipleCursors else { return false }
        let selection = selectedRange()
        let text = string as NSString
        guard selection.length == 0, selection.location > 0, selection.location < text.length,
              let previous = Unicode.Scalar(text.character(at: selection.location - 1)),
              let next = Unicode.Scalar(text.character(at: selection.location))
        else { return false }
        let pairing = pairing
        let open = Character(previous), close = Character(next)
        guard pairing.brackets[open] == close || (open == close && pairing.quotes.contains(open)) else { return false }
        insertText("", replacementRange: NSRange(location: selection.location - 1, length: 2))
        return true
    }
}
