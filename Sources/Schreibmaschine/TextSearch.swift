import Foundation

/// What to search for, and how.
struct SearchQuery: Equatable {
    var text: String
    var caseSensitive = false
    var wholeWords = false
    var regularExpression = false

    var isEmpty: Bool { text.isEmpty }

    enum Failure: Error, Equatable {
        /// The regular expression does not compile; the message says why, as far as ICU tells.
        case invalidPattern(String)
    }

    /// The query as a regular expression. Plain text is escaped, so every search runs the same way.
    func expression() throws -> NSRegularExpression {
        var pattern = regularExpression ? text : NSRegularExpression.escapedPattern(for: text)
        if wholeWords { pattern = "\\b(?:\(pattern))\\b" }
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if !caseSensitive { options.insert(.caseInsensitive) }
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw Failure.invalidPattern(Self.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        // ICU reports little more than "invalid pattern"; the common causes get a hint.
        String(localized: "Ungültiger regulärer Ausdruck. Klammern paarweise setzen, Sonderzeichen wie . * + ? ( ) [ ] mit \\ davor suchen.")
    }

    /// All matches in the range; empty matches (such as ^ or \b alone) are skipped.
    /// Stops at `limit` so a pathological pattern cannot stall the app.
    func matches(in string: String, range: NSRange? = nil, limit: Int = 100_000) throws -> [NSTextCheckingResult] {
        guard !isEmpty else { return [] }
        let expression = try expression()
        let range = range ?? NSRange(location: 0, length: (string as NSString).length)
        var results: [NSTextCheckingResult] = []
        expression.enumerateMatches(in: string, options: [], range: range) { result, _, stop in
            guard let result, result.range.length > 0 else { return }
            results.append(result)
            if results.count >= limit { stop.pointee = true }
        }
        return results
    }

    /// The text that replaces a match. With regular expressions, $1 and so on insert groups, and
    /// \n and \t stand for a line break and a tab; plain text is taken as it is.
    func replacement(for match: NSTextCheckingResult, in string: String, template: String) throws -> String {
        guard regularExpression else { return template }
        return try expression().replacementString(for: match, in: string, offset: 0, template: Self.expandEscapes(template))
    }

    /// \n, \t and \\ in a replacement template; other escapes, such as \$, are left to the template.
    static func expandEscapes(_ template: String) -> String {
        var result = ""
        var iterator = template.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let next = iterator.next() else {
                result.append(character)
                continue
            }
            switch next {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "\\": result.append("\\\\")
            default: result.append("\\"); result.append(next)
            }
        }
        return result
    }
}
