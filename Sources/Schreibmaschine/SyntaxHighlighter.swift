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

/// Finds the parts of a document to color, line by line, following its language.
///
/// Lines are colored when they are shown, so the cost does not grow with the document. A comment
/// or string can span lines, so each line starts in a state: inside such a region or not. These
/// states are computed from the top as far as needed and kept until an edit makes them invalid
/// from the edited line on.
final class SyntaxHighlighter {
    struct Token {
        let range: NSRange
        let scope: SyntaxScope
    }

    private(set) var language: LanguageDefinition?
    private unowned let storage: NSTextStorage
    private let lineIndex: LineIndex
    /// The state at the start of line n is at index n - 1: the rule of the region the line
    /// starts in, or nil. Line 1 always starts outside.
    private var startStates: [Int?] = [nil]

    init(storage: NSTextStorage, lineIndex: LineIndex) {
        self.storage = storage
        self.lineIndex = lineIndex
    }

    func setLanguage(_ language: LanguageDefinition?) {
        self.language = language
        startStates = [nil]
    }

    /// After an edit in the line, every following line may start differently.
    func invalidate(fromLine line: Int) {
        if startStates.count > line { startStates.removeSubrange(line...) }
    }

    /// The colored parts of a line, as ranges in the whole text.
    func tokens(forLine line: Int) -> [Token] {
        guard language != nil, line >= 1, line <= lineIndex.lineCount else { return [] }
        return scan(line: line, from: startState(ofLine: line), collect: true).tokens
    }

    private func startState(ofLine line: Int) -> Int? {
        while startStates.count < line {
            let known = startStates.count
            startStates.append(scan(line: known, from: startStates[known - 1], collect: false).endState)
        }
        return startStates[line - 1]
    }

    private func range(ofLine line: Int) -> NSRange {
        let start = lineIndex.start(ofLine: line)
        let end = line < lineIndex.lineCount ? lineIndex.start(ofLine: line + 1) - 1 : storage.length
        return NSRange(location: start, length: max(end - start, 0))
    }

    /// Goes through one line. Without `collect`, only what decides the state at its end is
    /// looked at: regions, comments and strings, not keywords or numbers.
    private func scan(line: Int, from state: Int?, collect: Bool) -> (tokens: [Token], endState: Int?) {
        guard let language else { return ([], nil) }
        let string = storage.string
        let lineRange = range(ofLine: line)
        var tokens: [Token] = []
        var position = lineRange.location
        let end = lineRange.upperBound

        // A region carried over from the line before.
        if let state, case .region(_, let endPattern, let escape, _, let scope) = language.rules[state] {
            if let close = findEnd(endPattern, escape: escape, in: string, from: position, to: end) {
                tokens.append(Token(range: NSRange(location: position, length: close - position), scope: scope))
                position = close
            } else {
                tokens.append(Token(range: lineRange, scope: scope))
                return (collect ? tokens : [], state)
            }
        }

        while position < end {
            // The rule matching earliest in the rest of the line wins; on a tie the first one.
            var best: (rule: Int, match: NSTextCheckingResult)?
            for (index, rule) in language.rules.enumerated() {
                let pattern: NSRegularExpression
                switch rule {
                case .match(let regex, _, let scope):
                    if !collect && scope != .comment && scope != .string { continue }
                    pattern = regex
                case .region(let begin, _, _, _, _):
                    pattern = begin
                }
                guard let match = pattern.firstMatch(in: string, options: [], range: NSRange(location: position, length: end - position)),
                      match.range.length > 0
                else { continue }
                if best == nil || match.range.location < best!.match.range.location {
                    best = (index, match)
                }
            }
            guard let (index, match) = best else { break }

            switch language.rules[index] {
            case .match(_, let group, let scope):
                let colored = group > 0 && group < match.numberOfRanges ? match.range(at: group) : match.range
                if colored.location != NSNotFound { tokens.append(Token(range: colored, scope: scope)) }
                position = match.range.upperBound
            case .region(_, let endPattern, let escape, let multiline, let scope):
                let contentStart = match.range.upperBound
                if let close = findEnd(endPattern, escape: escape, in: string, from: contentStart, to: end) {
                    tokens.append(Token(range: NSRange(location: match.range.location, length: close - match.range.location), scope: scope))
                    position = close
                } else {
                    tokens.append(Token(range: NSRange(location: match.range.location, length: end - match.range.location), scope: scope))
                    return (collect ? tokens : [], multiline ? index : nil)
                }
            }
        }
        return (collect ? tokens : [], nil)
    }

    /// Where a region ends: behind the first match of `end` that is not escaped.
    private func findEnd(_ end: NSRegularExpression, escape: Character?, in string: String, from start: Int, to limit: Int) -> Int? {
        let text = string as NSString
        let escapeUnit = escape.flatMap { $0.utf16.first }
        var position = start
        while position <= limit {
            guard let match = end.firstMatch(in: string, options: [], range: NSRange(location: position, length: limit - position)) else {
                return nil
            }
            if let escapeUnit {
                var backslashes = 0
                var index = match.range.location - 1
                while index >= start, text.character(at: index) == escapeUnit {
                    backslashes += 1
                    index -= 1
                }
                if backslashes % 2 == 1 {
                    position = match.range.location + max(match.range.length, 1)
                    continue
                }
            }
            return match.range.upperBound
        }
        return nil
    }
}
