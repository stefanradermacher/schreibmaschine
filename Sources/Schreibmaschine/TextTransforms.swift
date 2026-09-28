import Foundation

/// The transformations behind the Text menu, as plain functions on strings. Line-based ones get
/// the lines without their line breaks.
enum TextTransforms {
    // MARK: - Lines

    enum SortOrder { case ascending, descending, numeric }

    /// Sorting as people read: "Datei 2" before "Datei 10", case and accents only as a tiebreak.
    static func sort(_ lines: [String], _ order: SortOrder) -> [String] {
        switch order {
        case .ascending:
            return lines.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        case .descending:
            return lines.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        case .numeric:
            // By the first number in the line; lines without one keep their order at the end.
            let keyed = lines.enumerated().map { (offset: $0.offset, line: $0.element, number: firstNumber(in: $0.element)) }
            return keyed.sorted { a, b in
                switch (a.number, b.number) {
                case let (x?, y?): return x != y ? x < y : a.offset < b.offset
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.offset < b.offset
                }
            }.map(\.line)
        }
    }

    private static func firstNumber(in line: String) -> Double? {
        let scanner = Scanner(string: line)
        scanner.charactersToBeSkipped = nil
        while !scanner.isAtEnd {
            if let number = scanner.scanDouble() { return number }
            _ = scanner.scanCharacter()
        }
        return nil
    }

    /// Removes repeated lines, keeping the first of each.
    static func removeDuplicates(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.filter { seen.insert($0).inserted }
    }

    static func removeEmpty(_ lines: [String]) -> [String] {
        lines.filter { !$0.allSatisfy(\.isWhitespace) }
    }

    /// "1. " before every line, the numbers right-aligned.
    static func number(_ lines: [String]) -> [String] {
        let width = String(lines.count).count
        return lines.enumerated().map { index, line in
            let number = String(index + 1)
            return String(repeating: " ", count: width - number.count) + number + ". " + line
        }
    }

    /// Joins lines with the separator; the indentation of the following lines goes, as in
    /// PhpStorm. With a space as separator, no doubled spaces arise.
    static func join(_ lines: [String], separator: String) -> String {
        var result = ""
        for (index, line) in lines.enumerated() {
            if index == 0 {
                result = line
                continue
            }
            let part = String(line.drop { $0 == " " || $0 == "\t" })
            if separator == " " {
                while result.hasSuffix(" ") || result.hasSuffix("\t") { result.removeLast() }
                if !result.isEmpty && !part.isEmpty { result += " " }
                result += part
            } else {
                result += separator + part
            }
        }
        return result
    }

    /// Splits every line at the separator; spaces after it go.
    static func split(_ lines: [String], at separator: String) -> [String] {
        guard !separator.isEmpty else { return lines }
        return lines.flatMap { line -> [String] in
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            return line.components(separatedBy: separator).enumerated().map { index, part in
                index == 0 ? part : indent + part.drop { $0 == " " }
            }
        }
    }

    // MARK: - Indentation and quotes

    static func indent(_ lines: [String], unit: String) -> [String] {
        lines.map { $0.isEmpty ? $0 : unit + $0 }
    }

    /// Removes one level: a tab, or up to `width` spaces.
    static func outdent(_ lines: [String], width: Int) -> [String] {
        lines.map { line in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix(width).prefix { $0 == " " }.count
            return String(line.dropFirst(spaces))
        }
    }

    static func quote(_ lines: [String]) -> [String] {
        lines.map { $0.isEmpty ? ">" : "> " + $0 }
    }

    static func unquote(_ lines: [String]) -> [String] {
        lines.map { line in
            if line.hasPrefix("> ") { return String(line.dropFirst(2)) }
            if line.hasPrefix(">") { return String(line.dropFirst()) }
            return line
        }
    }

    // MARK: - Paragraphs

    /// The prefix a paragraph keeps on every line: indentation and quote marks.
    private static func linePrefix(of line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" || $0 == ">" })
    }

    /// Blocks of lines separated by empty lines; the empty lines stay as they are.
    private static func paragraphs(_ lines: [String]) -> [[String]] {
        var blocks: [[String]] = []
        var current: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: CharacterSet(charactersIn: " \t>")).isEmpty {
                if !current.isEmpty { blocks.append(current); current = [] }
                blocks.append([line])
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks
    }

    private static func isBlank(_ block: [String]) -> Bool {
        block.count == 1 && block[0].trimmingCharacters(in: CharacterSet(charactersIn: " \t>")).isEmpty
    }

    /// Wraps every paragraph at the column. Indentation and quote marks of its first line are
    /// kept on every line; after a list mark ("- ", "* ", "1. ") the lines are indented to the text.
    static func wrap(_ lines: [String], column: Int, tabWidth: Int) -> [String] {
        paragraphs(lines).flatMap { block -> [String] in
            guard !isBlank(block) else { return block }
            let first = block[0]
            let prefix = linePrefix(of: first)
            var body = String(first.dropFirst(prefix.count))
            let listMark = body.range(of: #"^([-*+]|\d+[.)]) "#, options: .regularExpression).map { String(body[$0]) }
            let continuation = prefix + String(repeating: " ", count: listMark?.count ?? 0)
            for line in block.dropFirst() {
                body += " " + line.dropFirst(linePrefix(of: line).count)
            }
            let words = body.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            var result: [String] = []
            var line = prefix
            var lineHasWord = false
            var remaining = words[...]
            if let listMark {
                line += listMark
                remaining = remaining.dropFirst()
            }
            for word in remaining {
                let candidate = lineHasWord ? line + " " + word : line + word
                if lineHasWord && displayWidth(candidate, tabWidth: tabWidth) > column {
                    result.append(line)
                    line = continuation + word
                } else {
                    line = candidate
                }
                lineHasWord = true
            }
            result.append(line)
            return result
        }
    }

    /// Joins the lines of every paragraph into one, keeping the prefix of its first line.
    static func unwrap(_ lines: [String]) -> [String] {
        paragraphs(lines).flatMap { block -> [String] in
            guard !isBlank(block), block.count > 1 else { return block }
            var result = block[0]
            for line in block.dropFirst() {
                let text = line.dropFirst(linePrefix(of: line).count).trimmingCharacters(in: .whitespaces)
                while result.hasSuffix(" ") { result.removeLast() }
                result += " " + text
            }
            return [result]
        }
    }

    private static func displayWidth(_ text: String, tabWidth: Int) -> Int {
        var column = 0
        for character in text {
            column = character == "\t" ? (column / tabWidth + 1) * tabWidth : column + 1
        }
        return column
    }

    // MARK: - White space

    static func trimTrailing(_ lines: [String]) -> [String] {
        lines.map { line in
            var line = line
            while line.last == " " || line.last == "\t" { line.removeLast() }
            return line
        }
    }

    /// Every tab becomes as many spaces as reach the next tab stop.
    static func tabsToSpaces(_ lines: [String], tabWidth: Int) -> [String] {
        lines.map { line in
            guard line.contains("\t") else { return line }
            var result = ""
            var column = 0
            for character in line {
                if character == "\t" {
                    let count = tabWidth - column % tabWidth
                    result += String(repeating: " ", count: count)
                    column += count
                } else {
                    result.append(character)
                    column += 1
                }
            }
            return result
        }
    }

    /// Indentation of spaces becomes tabs; spaces inside the line stay.
    static func spacesToTabs(_ lines: [String], tabWidth: Int) -> [String] {
        lines.map { line in
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let width = displayWidth(String(indent), tabWidth: tabWidth)
            return String(repeating: "\t", count: width / tabWidth) + String(repeating: " ", count: width % tabWidth) + line.dropFirst(indent.count)
        }
    }

    /// Runs of spaces inside a line become one; the indentation stays.
    static func collapseSpaces(_ lines: [String]) -> [String] {
        lines.map { line in
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let rest = line.dropFirst(indent.count).replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            return indent + rest
        }
    }

    // MARK: - Case

    enum Case { case upper, lower, sentence, title, camel, snake, kebab }

    static func changeCase(_ text: String, to style: Case) -> String {
        switch style {
        case .upper:
            return text.uppercased()
        case .lower:
            return text.lowercased()
        case .title:
            return text.capitalized
        case .sentence:
            // Lower case, with a capital at the start and after . ! ? and white space.
            let lower = text.lowercased() as NSString
            let result = NSMutableString(string: lower)
            let pattern = try! NSRegularExpression(pattern: #"(?:^|[.!?]\s+)(\p{L})"#, options: [.anchorsMatchLines])
            for match in pattern.matches(in: lower as String, range: NSRange(location: 0, length: lower.length)) {
                let letter = match.range(at: 1)
                result.replaceCharacters(in: letter, with: lower.substring(with: letter).uppercased())
            }
            return result as String
        case .camel, .snake, .kebab:
            // Line by line, so a list of names stays a list.
            return text.components(separatedBy: "\n").map { line -> String in
                let indent = String(line.prefix { $0 == " " || $0 == "\t" })
                let words = self.words(in: String(line.dropFirst(indent.count)))
                switch style {
                case .camel:
                    return indent + words.enumerated().map { $0.offset == 0 ? $0.element.lowercased() : $0.element.lowercased().capitalized }.joined()
                case .snake:
                    return indent + words.map { $0.lowercased() }.joined(separator: "_")
                default:
                    return indent + words.map { $0.lowercased() }.joined(separator: "-")
                }
            }.joined(separator: "\n")
        }
    }

    /// The words of a name, split at spaces, punctuation and changes from lower to upper case:
    /// "parseHTTPResponse" → parse, HTTP, Response.
    static func words(in text: String) -> [String] {
        var words: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current); current = "" }
                continue
            }
            if let last = current.last {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let lowerToUpper = last.isLowercase && character.isUppercase
                let acronymEnd = last.isUppercase && character.isUppercase && (next?.isLowercase ?? false)
                let letterDigit = last.isLetter != character.isLetter
                if lowerToUpper || acronymEnd || letterDigit {
                    words.append(current)
                    current = ""
                }
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    // MARK: - Columns

    /// Pads the lines so the first occurrence of the separator stands in the same column.
    static func align(_ lines: [String], at separator: String, tabWidth: Int) -> [String] {
        guard !separator.isEmpty else { return lines }
        let positions = lines.map { line -> Int? in
            guard let range = line.range(of: separator) else { return nil }
            var before = String(line[..<range.lowerBound])
            while before.hasSuffix(" ") { before.removeLast() }
            return displayWidth(before, tabWidth: tabWidth)
        }
        guard let target = positions.compactMap({ $0 }).max() else { return lines }
        return zip(lines, positions).map { line, position in
            guard let position, let range = line.range(of: separator) else { return line }
            var before = String(line[..<range.lowerBound])
            while before.hasSuffix(" ") { before.removeLast() }
            let after = line[range.lowerBound...]
            return before + String(repeating: " ", count: target - position + 1) + after
        }
    }

    /// Formats a Markdown table: cells padded to their column's width, the separator row
    /// rebuilt with its alignment colons.
    static func formatMarkdownTable(_ lines: [String]) -> [String] {
        let rows = lines.map { line -> [String] in
            var body = line.trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("|") { body.removeFirst() }
            if body.hasSuffix("|") && !body.hasSuffix("\\|") { body.removeLast() }
            // Split at | that is not escaped.
            var cells: [String] = []
            var cell = ""
            var escaped = false
            for character in body {
                if character == "|" && !escaped {
                    cells.append(cell.trimmingCharacters(in: .whitespaces))
                    cell = ""
                } else {
                    cell.append(character)
                }
                escaped = character == "\\" && !escaped
            }
            cells.append(cell.trimmingCharacters(in: .whitespaces))
            return cells
        }
        let isSeparator = { (row: [String]) in
            row.allSatisfy { $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil }
        }
        let columns = rows.map(\.count).max() ?? 0
        var widths = Array(repeating: 3, count: columns)
        for row in rows where !isSeparator(row) {
            for (index, cell) in row.enumerated() { widths[index] = max(widths[index], cell.count) }
        }
        // The colons of the separator row say how each column is aligned.
        enum Alignment { case left, right, center }
        let alignments: [Alignment] = (0..<columns).map { index in
            guard let row = rows.first(where: isSeparator), index < row.count else { return .left }
            let cell = row[index]
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): return .center
            case (false, true): return .right
            default: return .left
            }
        }
        return rows.map { row in
            let separator = isSeparator(row)
            let cells = (0..<columns).map { index -> String in
                let cell = index < row.count ? row[index] : ""
                guard separator else {
                    let space = widths[index] - cell.count
                    switch alignments[index] {
                    case .left: return cell + String(repeating: " ", count: space)
                    case .right: return String(repeating: " ", count: space) + cell
                    case .center: return String(repeating: " ", count: space / 2) + cell + String(repeating: " ", count: space - space / 2)
                    }
                }
                let left = cell.hasPrefix(":"), right = cell.hasSuffix(":")
                let dashes = widths[index] - (left ? 1 : 0) - (right ? 1 : 0)
                return (left ? ":" : "") + String(repeating: "-", count: max(dashes, 1)) + (right ? ":" : "")
            }
            return "| " + cells.joined(separator: " | ") + " |"
        }
    }

    // MARK: - Encoding

    enum Failure: LocalizedError {
        case notDecodable(String)
        var errorDescription: String? {
            if case .notDecodable(let message) = self { return message }
            return nil
        }
    }

    static func urlEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static func urlDecode(_ text: String) throws -> String {
        guard let decoded = text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
            throw Failure.notDecodable(String(localized: "Der Text enthält ungültige %-Folgen."))
        }
        return decoded
    }

    static func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    static func base64Decode(_ text: String) throws -> String {
        let compact = text.filter { !$0.isWhitespace }
        var padded = compact
        while padded.count % 4 != 0 { padded += "=" }
        guard let data = Data(base64Encoded: padded) else {
            throw Failure.notDecodable(String(localized: "Der Text ist kein gültiges Base64."))
        }
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw Failure.notDecodable(String(localized: "Die dekodierten Daten sind kein UTF-8-Text."))
        }
        return decoded
    }

    static func htmlEncode(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    private static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}",
        "copy": "©", "reg": "®", "trade": "™", "euro": "€", "hellip": "…", "ndash": "–", "mdash": "—",
        "laquo": "«", "raquo": "»", "bdquo": "„", "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "sbquo": "‚",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç", "deg": "°", "middot": "·", "times": "×", "shy": "\u{AD}",
    ]

    static func htmlDecode(_ text: String) -> String {
        let pattern = try! NSRegularExpression(pattern: "&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z]+);")
        let string = text as NSString
        var result = ""
        var last = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            result += string.substring(with: NSRange(location: last, length: match.range.location - last))
            let name = string.substring(with: match.range(at: 1))
            var replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = entities[name]
            }
            result += replacement ?? string.substring(with: match.range)
            last = match.range.upperBound
        }
        result += string.substring(from: last)
        return result
    }

    /// Checks the text for JSON and reports where it is broken.
    private static func validateJSON(_ text: String) throws {
        do {
            _ = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        } catch let error as NSError {
            let detail = error.userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
            throw Failure.notDecodable(String(localized: "Kein gültiges JSON: \(detail)"))
        }
    }

    /// Indents JSON anew. The keys keep their order: the text is re-indented, not parsed and
    /// written again.
    static func formatJSON(_ text: String, indent: String) throws -> String {
        try validateJSON(text)
        var result = ""
        var level = 0
        var inString = false
        var escaped = false
        let characters = Array(text)
        var index = 0
        func newline() { result += "\n" + String(repeating: indent, count: level) }
        while index < characters.count {
            let character = characters[index]
            if inString {
                result.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                index += 1
                continue
            }
            switch character {
            case "\"":
                inString = true
                result.append(character)
            case "{", "[":
                // Empty objects and arrays stay on one line.
                var next = index + 1
                while next < characters.count, characters[next].isWhitespace { next += 1 }
                if next < characters.count, characters[next] == (character == "{" ? "}" : "]") {
                    result += character == "{" ? "{}" : "[]"
                    index = next
                } else {
                    result.append(character)
                    level += 1
                    newline()
                }
            case "}", "]":
                level -= 1
                newline()
                result.append(character)
            case ",":
                result.append(character)
                newline()
            case ":":
                result += ": "
            case _ where character.isWhitespace:
                break
            default:
                result.append(character)
            }
            index += 1
        }
        return result
    }

    static func minifyJSON(_ text: String) throws -> String {
        try validateJSON(text)
        var result = ""
        var inString = false
        var escaped = false
        for character in text {
            if inString {
                result.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
                result.append(character)
            } else if !character.isWhitespace {
                result.append(character)
            }
        }
        return result
    }
}
