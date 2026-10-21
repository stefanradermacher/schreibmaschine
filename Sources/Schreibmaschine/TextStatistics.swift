import Foundation

/// Counting words, characters, lines and paragraphs, for the status bar.
struct TextStatistics: Equatable {
    var words = 0
    var characters = 0
    var charactersWithoutSpaces = 0
    var lines = 0
    var paragraphs = 0

    enum Unit: String, CaseIterable {
        case words, characters, charactersWithoutSpaces, lines, paragraphs

        /// "1.234 Wörter" for the whole text.
        func total(_ count: Int) -> String {
            let n = count.formatted()
            switch self {
            case .words: return count == 1 ? String(localized: "1 Wort") : String(localized: "\(n) Wörter")
            case .characters: return count == 1 ? String(localized: "1 Zeichen") : String(localized: "\(n) Zeichen")
            case .charactersWithoutSpaces: return String(localized: "\(n) Zeichen ohne Leerzeichen")
            case .lines: return count == 1 ? String(localized: "1 Zeile") : String(localized: "\(n) Zeilen")
            case .paragraphs: return count == 1 ? String(localized: "1 Absatz") : String(localized: "\(n) Absätze")
            }
        }

        /// "12 von 1.234 Wörtern" for a selection.
        func part(_ part: Int, of total: Int) -> String {
            let p = part.formatted(), n = total.formatted()
            switch self {
            case .words: return String(localized: "\(p) von \(n) Wörtern")
            case .characters: return String(localized: "\(p) von \(n) Zeichen")
            case .charactersWithoutSpaces: return String(localized: "\(p) von \(n) Zeichen ohne Leerzeichen")
            case .lines: return String(localized: "\(p) von \(n) Zeilen")
            case .paragraphs: return String(localized: "\(p) von \(n) Absätzen")
            }
        }
    }

    func value(_ unit: Unit) -> Int {
        switch unit {
        case .words: words
        case .characters: characters
        case .charactersWithoutSpaces: charactersWithoutSpaces
        case .lines: lines
        case .paragraphs: paragraphs
        }
    }

    /// Words as the system's word boundaries see them, characters as the reader counts them
    /// (an emoji or an accented letter is one), paragraphs as runs of non-empty lines.
    init(of text: String) {
        guard !text.isEmpty else { return }
        let string = text as NSString
        var wordCount = 0
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            wordCount += 1
        }
        words = wordCount
        var inParagraph = false
        var lineHasText = false
        lines = 1
        for character in text {
            characters += 1
            if character.isNewline {
                lines += 1
                if !lineHasText { inParagraph = false }
                lineHasText = false
                continue
            }
            if !character.isWhitespace {
                charactersWithoutSpaces += 1
                if !lineHasText, !inParagraph { paragraphs += 1; inParagraph = true }
                lineHasText = true
            }
        }
        // A final line break does not start another line for the reader.
        if text.hasSuffix("\n") { lines -= 1 }
    }

    init() {}
}
