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

import Foundation

/// A value from a YAML file: text, a list or a mapping. Mappings keep the order of their keys.
enum YAMLValue: Equatable {
    case scalar(String)
    case list([YAMLValue])
    case map([YAMLEntry])

    subscript(key: String) -> YAMLValue? {
        guard case .map(let entries) = self else { return nil }
        return entries.first { $0.key == key }?.value
    }

    var string: String? {
        if case .scalar(let text) = self { return text }
        return nil
    }

    /// A list of texts; a single text counts as a list with one entry.
    var strings: [String]? {
        switch self {
        case .scalar(let text): [text]
        case .list(let items): items.compactMap(\.string)
        case .map: nil
        }
    }

    var bool: Bool? {
        switch string?.lowercased() {
        case "true", "yes", "on": true
        case "false", "no", "off": false
        default: nil
        }
    }

    var int: Int? { string.flatMap { Int($0) } }
}

struct YAMLEntry: Equatable {
    let key: String
    let value: YAMLValue
}

struct YAMLError: LocalizedError {
    let line: Int
    let message: String

    var errorDescription: String? { String(localized: "Zeile \(line): \(message)") }
}

/// Reads the part of YAML that language definitions need: mappings and lists by indentation,
/// lists in square brackets, text plain or in single or double quotes, block text with | and >,
/// and comments. Anything else is reported with its line number.
enum YAML {
    static func parse(_ text: String) throws -> YAMLValue {
        var parser = Parser(lines: text.normalizingLineEndings.components(separatedBy: "\n"))
        let value = try parser.parseBlock(minIndent: 0) ?? .map([])
        parser.skipInsignificant()
        if parser.index < parser.lines.count {
            throw YAMLError(line: parser.index + 1, message: String(localized: "Unerwartete Einrückung."))
        }
        return value
    }

    private struct Parser {
        var lines: [String]
        var index = 0

        // MARK: Lines

        /// The line without its comment and without surrounding white space.
        func content(_ index: Int) -> String {
            var inSingle = false, inDouble = false
            var previous: Character = " "
            var result = ""
            for character in lines[index] {
                if character == "'" && !inDouble { inSingle.toggle() }
                if character == "\"" && !inSingle && previous != "\\" { inDouble.toggle() }
                if character == "#" && !inSingle && !inDouble && previous.isWhitespace { break }
                result.append(character)
                previous = character
            }
            return result.trimmingCharacters(in: .whitespaces)
        }

        func indent(_ index: Int) -> Int {
            lines[index].prefix { $0 == " " }.count
        }

        func isSignificant(_ index: Int) -> Bool {
            !content(index).isEmpty
        }

        mutating func skipInsignificant() {
            while index < lines.count, !isSignificant(index) { index += 1 }
        }

        // MARK: Blocks

        mutating func parseBlock(minIndent: Int) throws -> YAMLValue? {
            skipInsignificant()
            guard index < lines.count else { return nil }
            if lines[index].prefix(while: { $0 == " " || $0 == "\t" }).contains("\t") {
                throw YAMLError(line: index + 1, message: String(localized: "Tabs sind zum Einrücken nicht erlaubt, bitte Leerzeichen verwenden."))
            }
            let indent = indent(index)
            guard indent >= minIndent else { return nil }
            let text = content(index)
            if text == "-" || text.hasPrefix("- ") {
                return try parseList(indent: indent)
            }
            return try parseMap(indent: indent)
        }

        mutating func parseList(indent: Int) throws -> YAMLValue {
            var items: [YAMLValue] = []
            while true {
                skipInsignificant()
                guard index < lines.count, self.indent(index) == indent else { break }
                let text = content(index)
                guard text == "-" || text.hasPrefix("- ") else { break }
                let rest = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                if rest.isEmpty {
                    index += 1
                    items.append(try parseBlock(minIndent: indent + 1) ?? .scalar(""))
                } else if Self.splitKey(rest) != nil {
                    // "- key: value" starts a mapping that continues on the following lines.
                    lines[index] = String(repeating: " ", count: indent + 2) + rest
                    items.append(try parseMap(indent: indent + 2))
                } else {
                    items.append(try Self.scalar(rest, line: index + 1))
                    index += 1
                }
            }
            return .list(items)
        }

        mutating func parseMap(indent: Int) throws -> YAMLValue {
            var entries: [YAMLEntry] = []
            while true {
                skipInsignificant()
                guard index < lines.count else { break }
                let lineIndent = self.indent(index)
                if lineIndent < indent { break }
                if lineIndent > indent {
                    throw YAMLError(line: index + 1, message: String(localized: "Unerwartete Einrückung."))
                }
                let text = content(index)
                if text.hasPrefix("- ") || text == "-" { break }
                guard let (key, firstRest) = Self.splitKey(text) else {
                    throw YAMLError(line: index + 1, message: String(localized: "Erwartet wird „Schlüssel: Wert“."))
                }
                if entries.contains(where: { $0.key == key }) {
                    throw YAMLError(line: index + 1, message: String(localized: "Der Schlüssel „\(key)“ steht doppelt."))
                }
                let line = index + 1
                index += 1
                var rest = firstRest
                // A list in square brackets may continue on the following lines.
                if rest.hasPrefix("[") && !rest.hasSuffix("]") {
                    while index < lines.count {
                        let next = content(index)
                        index += 1
                        rest += " " + next
                        if next.hasSuffix("]") { break }
                    }
                }
                let value: YAMLValue
                if rest.isEmpty {
                    skipInsignificant()
                    // A list may start at the same indentation as its key.
                    if index < lines.count, self.indent(index) == indent, content(index).hasPrefix("-") {
                        value = try parseList(indent: indent)
                    } else {
                        value = try parseBlock(minIndent: indent + 1) ?? .scalar("")
                    }
                } else if let style = rest.first, style == "|" || style == ">", rest.count <= 2 {
                    value = .scalar(blockScalar(parentIndent: indent, folded: style == ">", strip: rest.hasSuffix("-")))
                } else {
                    value = try Self.scalar(rest, line: line)
                }
                entries.append(YAMLEntry(key: key, value: value))
            }
            return .map(entries)
        }

        /// Text after | or >: the following lines indented deeper than the key, as they are.
        mutating func blockScalar(parentIndent: Int, folded: Bool, strip: Bool) -> String {
            var collected: [String] = []
            var contentIndent: Int?
            while index < lines.count {
                let line = lines[index]
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    collected.append("")
                    index += 1
                    continue
                }
                let lineIndent = line.prefix { $0 == " " }.count
                guard lineIndent > parentIndent else { break }
                if contentIndent == nil { contentIndent = lineIndent }
                collected.append(String(line.dropFirst(min(lineIndent, contentIndent!))))
                index += 1
            }
            while collected.last == "" { collected.removeLast() }
            let text = folded ? collected.joined(separator: " ") : collected.joined(separator: "\n")
            return strip || text.isEmpty ? text : text + "\n"
        }

        // MARK: Scalars

        /// Splits "key: value" at the colon; the key may be quoted.
        static func splitKey(_ text: String) -> (String, String)? {
            var inSingle = false, inDouble = false
            var index = text.startIndex
            while index < text.endIndex {
                let character = text[index]
                if character == "'" && !inDouble { inSingle.toggle() }
                if character == "\"" && !inSingle { inDouble.toggle() }
                if character == ":" && !inSingle && !inDouble {
                    let next = text.index(after: index)
                    if next == text.endIndex || text[next] == " " {
                        var key = String(text[..<index]).trimmingCharacters(in: .whitespaces)
                        if key.count >= 2, let first = key.first, first == key.last, first == "\"" || first == "'" {
                            key = String(key.dropFirst().dropLast())
                        }
                        guard !key.isEmpty, !key.hasPrefix("[") else { return nil }
                        let rest = next == text.endIndex ? "" : String(text[next...]).trimmingCharacters(in: .whitespaces)
                        return (key, rest)
                    }
                }
                index = text.index(after: index)
            }
            return nil
        }

        static func scalar(_ text: String, line: Int) throws -> YAMLValue {
            if text.hasPrefix("[") {
                guard text.hasSuffix("]") else {
                    throw YAMLError(line: line, message: String(localized: "Die Liste in eckigen Klammern ist nicht geschlossen."))
                }
                return .list(try splitFlow(String(text.dropFirst().dropLast()), line: line).map { .scalar($0) })
            }
            if text.hasPrefix("{") {
                throw YAMLError(line: line, message: String(localized: "Zuordnungen in geschweiften Klammern werden nicht unterstützt; bitte eingerückt schreiben."))
            }
            return .scalar(try unquote(text, line: line))
        }

        static func unquote(_ text: String, line: Int) throws -> String {
            if text.hasPrefix("'") {
                guard text.count >= 2, text.hasSuffix("'") else {
                    throw YAMLError(line: line, message: String(localized: "Das einfache Anführungszeichen ist nicht geschlossen."))
                }
                return String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
            if text.hasPrefix("\"") {
                guard text.count >= 2, text.hasSuffix("\"") else {
                    throw YAMLError(line: line, message: String(localized: "Das doppelte Anführungszeichen ist nicht geschlossen."))
                }
                var result = ""
                var escaped = false
                for character in text.dropFirst().dropLast() {
                    if escaped {
                        switch character {
                        case "n": result.append("\n")
                        case "t": result.append("\t")
                        case "\\": result.append("\\")
                        case "\"": result.append("\"")
                        default: result.append("\\"); result.append(character)
                        }
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else {
                        result.append(character)
                    }
                }
                return result
            }
            return text == "~" || text == "null" ? "" : text
        }

        /// The items of [a, 'b', "c"], split at commas outside quotes.
        static func splitFlow(_ text: String, line: Int) throws -> [String] {
            var items: [String] = []
            var current = ""
            var inSingle = false, inDouble = false
            var previous: Character = " "
            for character in text {
                if character == "'" && !inDouble { inSingle.toggle() }
                if character == "\"" && !inSingle && previous != "\\" { inDouble.toggle() }
                if character == "," && !inSingle && !inDouble {
                    items.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
                previous = character
            }
            items.append(current)
            return try items
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { try unquote($0, line: line) }
        }
    }
}
