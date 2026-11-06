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

/// An entry of the outline: a heading, function, or class, found by the outline rules of the
/// document's language.
struct OutlineItem {
    let name: String
    /// 0 for the top level.
    let level: Int
    let location: Int
    let line: Int
}

enum Outline {
    /// The outline of a document, in the order of the text. Matches inside comments, strings,
    /// and code blocks do not count, unless the rule is meant for comments.
    static func items(in document: TextDocument) -> [OutlineItem] {
        guard let language = document.language, !language.outline.isEmpty else { return [] }
        let text = document.textStorage.string
        let string = text as NSString
        let width = max(document.indentation.width, 1)
        var found: [(name: String, level: Int, location: Int, line: Int)] = []
        var seen = Set<Int>()
        var tokens: [Int: [SyntaxHighlighter.Token]] = [:]
        for rule in language.outline {
            for match in rule.expression.matches(in: text, range: NSRange(location: 0, length: string.length)) {
                let nameRange = rule.nameGroup < match.numberOfRanges ? match.range(at: rule.nameGroup) : match.range
                guard nameRange.location != NSNotFound, !seen.contains(match.range.location) else { continue }
                let line = document.lineIndex.lineNumber(at: match.range.location)
                let lineTokens = tokens[line] ?? document.highlighter.tokens(forLine: line)
                tokens[line] = lineTokens
                let scope = lineTokens.first { NSLocationInRange(nameRange.location, $0.range) }?.scope
                if rule.inComment {
                    guard scope == .comment else { continue }
                } else if let scope, [.comment, .string, .code].contains(scope) {
                    continue
                }
                let name = string.substring(with: nameRange)
                    .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
                guard !name.isEmpty else { continue }
                let level: Int
                if let group = rule.levelGroup, group < match.numberOfRanges, match.range(at: group).location != NSNotFound {
                    let value = string.substring(with: match.range(at: group))
                    level = Int(value) ?? (value as NSString).length
                } else {
                    level = indentColumns(at: document.lineIndex.start(ofLine: line), in: string, width: width) / width
                }
                seen.insert(match.range.location)
                found.append((name, level, match.range.location, line))
            }
        }
        found.sort { $0.location < $1.location }
        // The highest level present is the top: a Markdown text may start with ##.
        let top = found.map(\.level).min() ?? 0
        return found.map { OutlineItem(name: $0.name, level: $0.level - top, location: $0.location, line: $0.line) }
    }

    private static func indentColumns(at start: Int, in text: NSString, width: Int) -> Int {
        var columns = 0
        var index = start
        while index < text.length {
            switch text.character(at: index) {
            case 0x20: columns += 1
            case 0x09: columns = (columns / width + 1) * width
            default: return columns
            }
            index += 1
        }
        return columns
    }
}

// MARK: - Going to an entry

extension EditorViewController {
    /// The entry the insertion point is in: the last one before it.
    var currentOutlineIndex: (items: [OutlineItem], index: Int?) {
        let items = Outline.items(in: document)
        let caret = textView.selectedRange().location
        return (items, items.lastIndex { $0.location <= caret })
    }

    func reveal(_ item: OutlineItem) {
        let text = textView.string as NSString
        guard item.location <= text.length else { return }
        let range = NSRange(location: item.location, length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.centerSelectionInVisibleArea(nil)
        textView.showFindIndicator(for: text.lineRange(for: range))
    }
}
