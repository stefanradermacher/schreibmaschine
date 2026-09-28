import Foundation

/// How a document indents: with spaces or tabs, and how wide one level is.
struct Indentation: Equatable, Codable {
    var width: Int
    var usesSpaces: Bool

    /// One level of indentation as text.
    var unit: String { usesSpaces ? String(repeating: " ", count: width) : "\t" }

    static var preferred: Indentation {
        Indentation(width: Preferences.tabWidthValue, usesSpaces: Preferences.indentsWithSpacesValue)
    }

    /// The indentation a text already uses, from its first few thousand lines: tabs if most
    /// indented lines start with a tab, otherwise the most common step between the indentation
    /// of neighbouring lines. nil if the text is not indented.
    static func detect(in text: String, fallbackWidth: Int) -> Indentation? {
        var tabLines = 0, spaceLines = 0
        var steps: [Int: Int] = [:]
        var previous = 0
        var checked = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            checked += 1
            if checked > 5000 { break }
            guard line.contains(where: { !$0.isWhitespace }) else { continue }
            if line.hasPrefix("\t") {
                tabLines += 1
                continue
            }
            let spaces = line.prefix { $0 == " " }.count
            // " * " continues a block comment and says nothing about the indentation.
            let rest = line.dropFirst(spaces)
            if rest.hasPrefix("*") { continue }
            if spaces > 0 { spaceLines += 1 }
            let step = abs(spaces - previous)
            if step >= 2 && step <= 8 { steps[step, default: 0] += 1 }
            previous = spaces
        }
        if tabLines == 0 && spaceLines == 0 { return nil }
        if tabLines > spaceLines { return Indentation(width: fallbackWidth, usesSpaces: false) }
        // On a tie the order decides: 2 before 4 before 3 before 8.
        let width = [2, 4, 3, 8].max { (steps[$0] ?? 0) < (steps[$1] ?? 0) } ?? fallbackWidth
        return Indentation(width: (steps[width] ?? 0) > 0 ? width : fallbackWidth, usesSpaces: true)
    }
}
