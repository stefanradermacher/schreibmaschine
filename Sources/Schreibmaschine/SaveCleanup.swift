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

/// Tidying up when saving, if the settings want it: spaces and tabs at the ends of lines go,
/// and the file ends with a line break. It is an edit in the text like any other, undone with
/// ⌘Z, so the text and the file stay the same.
extension TextDocument {
    private static let trailingWhitespace = try! NSRegularExpression(pattern: "[ \\t]+$", options: .anchorsMatchLines)

    func tidyUpBeforeSaving() {
        let trims = UserDefaults.standard.bool(forKey: Preferences.trimsTrailingWhitespace)
        let endsWithLineBreak = UserDefaults.standard.bool(forKey: Preferences.endsWithLineBreak)
        guard trims || endsWithLineBreak, let editor, let textView = editor.panes.first?.textView else { return }
        let text = textStorage.string as NSString
        var edits: [(range: NSRange, text: String)] = []
        if trims {
            // Lines with an insertion point keep their spaces: someone may be typing there, and
            // saving automatically would take the space before the next word away.
            let carets = editor.panes.flatMap { $0.textView.editingRanges }
            let isMarkdown = language?.id == "markdown"
            for match in Self.trailingWhitespace.matches(in: textStorage.string, range: NSRange(location: 0, length: text.length)) {
                let line = text.lineRange(for: match.range)
                if carets.contains(where: { NSLocationInRange($0.location, line) || $0.location == NSMaxRange(line) && NSMaxRange(line) == text.length }) {
                    continue
                }
                // Two spaces at the end of a line of Markdown are a line break.
                if isMarkdown, match.range.length >= 2, match.range.location > line.location,
                   text.substring(with: match.range).allSatisfy({ $0 == " " }) {
                    continue
                }
                edits.append((match.range, ""))
            }
        }
        if endsWithLineBreak, text.length > 0, text.character(at: text.length - 1) != 0x0A {
            edits.append((NSRange(location: text.length, length: 0), "\n"))
        }
        guard !edits.isEmpty,
              textView.shouldChangeText(inRanges: edits.map { NSValue(range: $0.range) }, replacementStrings: edits.map(\.text))
        else { return }
        // The insertion points of every view, moved along with the text before them.
        let selections = editor.panes.map { pane in
            pane.textView.editingRanges.map { range -> NSRange in
                let shift = edits.filter { $0.range.upperBound <= range.location }
                    .reduce(0) { $0 + ($1.text as NSString).length - $1.range.length }
                return NSRange(location: range.location + shift, length: range.length)
            }
        }
        textStorage.beginEditing()
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            textStorage.replaceCharacters(in: edit.range, with: edit.text)
        }
        textStorage.endEditing()
        textView.didChangeText()
        undoManager?.setActionName(String(localized: "Beim Sichern aufräumen"))
        for (pane, ranges) in zip(editor.panes, selections) {
            pane.textView.setCursorRanges(ranges)
        }
    }
}
