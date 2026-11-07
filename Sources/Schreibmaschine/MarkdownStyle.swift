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

/// Markdown shown with its formatting: headings larger and bold, bold and italic text as such,
/// code with a background, links in the link color. Every character stays where it is and can
/// be edited as usual; the marks (#, **, `, link targets) are only faded. The file is not
/// touched: the formatting lives in the attributes of the text storage, which are not saved.
///
/// The whole text is styled when it is shown, and after an edit the edited lines.
final class MarkdownStyler {
    /// Whether Markdown documents are shown formatted.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: Preferences.stylesMarkdown) }

    /// Above this size the text is left as it is.
    static let longestStyledText = 5_000_000

    static func applies(to document: TextDocument) -> Bool {
        isEnabled && document.language?.id == "markdown" && document.textStorage.length <= longestStyledText
    }

    private let document: TextDocument?
    private let storage: NSTextStorage
    private var applies: Bool { document.map(Self.applies) ?? true }
    /// The attributes of plain text, with the editor's font and line height.
    var base: [NSAttributedString.Key: Any] = EditorStyle.attributes()
    var lineHeight: Double = Preferences.lineHeightValue
    private var observer: NSObjectProtocol?
    private var isStyling = false
    private var fenceCount = 0

    init(document: TextDocument) {
        self.document = document
        storage = document.textStorage
        observer = NotificationCenter.default.addObserver(forName: NSTextStorage.willProcessEditingNotification,
                                                          object: document.textStorage, queue: nil) { [weak self] _ in
            self?.storageWillProcessEditing()
        }
    }

    /// For a copy of the text, such as for printing.
    private init(storage: NSTextStorage) {
        document = nil
        self.storage = storage
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// The text styled with the given plain-text attributes, without touching any document.
    static func styled(_ text: String, base: [NSAttributedString.Key: Any], lineHeight: Double) -> NSTextStorage {
        let storage = NSTextStorage(string: text, attributes: base)
        let styler = MarkdownStyler(storage: storage)
        styler.base = base
        styler.lineHeight = lineHeight
        styler.restyleAll()
        return storage
    }

    /// Styles the whole text anew, or takes the formatting away if it does not apply.
    func restyleAll() {
        let all = NSRange(location: 0, length: storage.length)
        isStyling = true
        defer { isStyling = false }
        storage.beginEditing()
        if applies {
            fenceCount = countFences()
            style(all)
        } else {
            reset(all)
        }
        storage.endEditing()
    }

    // MARK: - After an edit

    /// Called while TextKit processes an edit. The edited lines are styled right after it, in
    /// the same pass of the run loop, so typed text never shows up unformatted. Styling during
    /// the edit would widen the edited range, and the text view would put the insertion point
    /// at its end.
    private func storageWillProcessEditing() {
        guard !isStyling, storage.editedMask.contains(.editedCharacters), applies else { return }
        let text = storage.string as NSString
        let paragraph = text.paragraphRange(for: storage.editedRange)
        // The range to style, kept as a start and a distance from the end, so that later edits
        // before the styling do not make it wrong.
        let tail = text.length - paragraph.upperBound
        if let pending = pendingStyle {
            pendingStyle = (min(pending.start, paragraph.location), min(pending.tail, tail))
            return
        }
        pendingStyle = (paragraph.location, tail)
        DispatchQueue.main.async { [weak self] in self?.stylePending() }
    }

    private var pendingStyle: (start: Int, tail: Int)?

    private func stylePending() {
        guard let pending = pendingStyle else { return }
        pendingStyle = nil
        guard applies else { return }
        let text = storage.string as NSString
        let start = min(pending.start, text.length)
        var range = text.paragraphRange(for: NSRange(location: start, length: max(0, text.length - pending.tail - start)))
        // A code fence opened or closed changes every line after it.
        let fences = countFences()
        if fences != fenceCount {
            fenceCount = fences
            range = NSRange(location: range.location, length: text.length - range.location)
        }
        isStyling = true
        defer { isStyling = false }
        storage.beginEditing()
        style(range)
        storage.endEditing()
    }

    private func countFences() -> Int {
        Self.fence.numberOfMatches(in: storage.string, range: NSRange(location: 0, length: storage.length))
    }

    // MARK: - Styling

    /// How deep a line is quoted; the layout fragment draws a bar for each level.
    static let quoteDepth = NSAttributedString.Key("SchreibmaschineQuoteDepth")
    /// Room for one quote bar, left of the text.
    static let quoteBarStep: CGFloat = 12

    private static let keys: [NSAttributedString.Key] = [.font, .paragraphStyle, .baselineOffset, .foregroundColor,
                                                         .backgroundColor, .strikethroughStyle, .obliqueness, quoteDepth]

    private func reset(_ range: NSRange) {
        for key in Self.keys { storage.removeAttribute(key, range: range) }
        storage.addAttributes(base, range: range)
    }

    private func style(_ range: NSRange) {
        reset(range)
        let text = storage.string as NSString
        // Whether the first line is inside a fenced code block: an odd number of fences before it.
        var inFence = Self.fence.numberOfMatches(in: storage.string, range: NSRange(location: 0, length: range.location)) % 2 == 1
        var location = range.location
        while location < range.upperBound {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            var contentsEnd = 0
            text.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: line)
            let content = NSRange(location: line.location, length: contentsEnd - line.location)
            if content.length <= SyntaxHighlighter.longestColoredLine {
                if Self.fence.firstMatch(in: storage.string, range: line) != nil {
                    inFence.toggle()
                    storage.addAttribute(.foregroundColor, value: Self.markColor, range: content)
                } else if inFence {
                    storage.addAttribute(.backgroundColor, value: Self.codeBackground, range: content)
                } else {
                    styleLine(content, in: text)
                }
            }
            location = line.upperBound
            if line.length == 0 { break }
        }
    }

    private func styleLine(_ line: NSRange, in text: NSString) {
        let string = storage.string
        func match(_ expression: NSRegularExpression, in range: NSRange = line) -> NSTextCheckingResult? {
            expression.firstMatch(in: string, range: range)
        }
        var rest = line
        if let heading = match(Self.heading) {
            let level = heading.range(at: 1).length
            styleHeading(line, level: level)
            fade(heading.range)
            rest = NSRange(location: heading.range.upperBound, length: line.upperBound - heading.range.upperBound)
        } else if match(Self.rule) != nil {
            fade(line)
            return
        } else if let quote = match(Self.quote) {
            fade(quote.range)
            let content = NSRange(location: quote.range.upperBound, length: line.upperBound - quote.range.upperBound)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: content)
            convert(content, to: .italicFontMask)
            let depth = (storage.string as NSString).substring(with: quote.range).filter { $0 == ">" }.count
            let paragraph = (storage.string as NSString).paragraphRange(for: line)
            storage.addAttribute(Self.quoteDepth, value: depth, range: paragraph)
            let bars = CGFloat(depth) * Self.quoteBarStep
            indent(paragraph, first: bars, wrapped: bars + width(of: quote.range))
            rest = content
        } else if let item = match(Self.listItem) {
            fade(item.range(at: 1))
            if item.range(at: 2).location != NSNotFound { fade(item.range(at: 2)) }
            // Wrapped lines of a list item start below its text, not below the mark.
            indent((storage.string as NSString).paragraphRange(for: line), first: 0, wrapped: width(of: item.range))
            rest = NSRange(location: item.range.upperBound, length: line.upperBound - item.range.upperBound)
        }
        styleInline(rest)
    }

    /// The width of a part of a line, as it is set.
    private func width(of range: NSRange) -> CGFloat {
        storage.attributedSubstring(from: range).size().width.rounded(.up)
    }

    private func indent(_ paragraph: NSRange, first: CGFloat, wrapped: CGFloat) {
        let current = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
        let style = ((current ?? base[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        style.firstLineHeadIndent = first
        style.headIndent = wrapped
        storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
    }

    /// Code spans first: inside them nothing else counts.
    private func styleInline(_ range: NSRange) {
        guard range.length > 0 else { return }
        let string = storage.string
        var code: [NSRange] = []
        for span in Self.codeSpan.matches(in: string, range: range) {
            code.append(span.range)
            storage.addAttribute(.backgroundColor, value: Self.codeBackground, range: span.range)
            fade(span.range(at: 1))
            fade(span.range(at: 3))
        }
        func free(_ match: NSTextCheckingResult) -> Bool {
            !code.contains { NSIntersectionRange($0, match.range).length > 0 }
        }
        for link in Self.link.matches(in: string, range: range) where free(link) {
            fade(link.range(at: 1))
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: link.range(at: 2))
            fade(link.range(at: 3))
        }
        for url in Self.url.matches(in: string, range: range) where free(url) {
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: url.range)
        }
        for bold in Self.bold.matches(in: string, range: range) where free(bold) {
            convert(bold.range, to: .boldFontMask)
            fade(bold.range(at: 1))
            fade(bold.range(at: 3))
        }
        for expression in [Self.italicStar, Self.italicUnderscore] {
            for italic in expression.matches(in: string, range: range) where free(italic) {
                convert(italic.range, to: .italicFontMask)
                fade(NSRange(location: italic.range.location, length: 1))
                fade(NSRange(location: italic.range.upperBound - 1, length: 1))
            }
        }
        for strike in Self.strike.matches(in: string, range: range) where free(strike) {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: strike.range(at: 2))
            fade(strike.range(at: 1))
            fade(strike.range(at: 3))
        }
    }

    private func styleHeading(_ line: NSRange, level: Int) {
        guard let font = base[.font] as? NSFont else { return }
        let scale: CGFloat = [1.6, 1.35, 1.15, 1.05, 1, 1][min(level, 6) - 1]
        let size = (font.pointSize * scale).rounded()
        let larger = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
        let heading = NSFontManager.shared.convert(larger, toHaveTrait: .boldFontMask)
        let height = EditorStyle.lineHeightPoints(font: heading, multiple: lineHeight)
        let style = ((base[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        let paragraph = (storage.string as NSString).paragraphRange(for: line)
        storage.addAttributes([
            .font: heading,
            .paragraphStyle: style,
            .baselineOffset: ((height - EditorStyle.naturalLineHeight(of: heading)) / 2).rounded(),
        ], range: paragraph)
    }

    /// Makes the fonts in the range bold or italic, keeping their size. A font without italics
    /// is slanted instead.
    private func convert(_ range: NSRange, to trait: NSFontTraitMask) {
        guard range.length > 0 else { return }
        storage.enumerateAttribute(.font, in: range) { value, part, _ in
            guard let font = value as? NSFont else { return }
            let converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: part)
            if trait == .italicFontMask, !NSFontManager.shared.traits(of: converted).contains(.italicFontMask) {
                storage.addAttribute(.obliqueness, value: 0.18, range: part)
            }
        }
    }

    private func fade(_ range: NSRange) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: Self.markColor, range: range)
    }

    // MARK: - Look

    static let markColor = NSColor.tertiaryLabelColor
    static let codeBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.05)
    }

    // MARK: - Patterns

    private static func pattern(_ string: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: string, options: options)
    }

    private static let fence = pattern(#"^[ \t]*(?:```|~~~)"#, .anchorsMatchLines)
    private static let heading = pattern(#"^(#{1,6})[ \t]+"#)
    private static let rule = pattern(#"^[ \t]*(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,}|={3,})$"#)
    private static let quote = pattern(#"^[ \t]*(?:>[ \t]?)+"#)
    private static let listItem = pattern(#"^[ \t]*([-*+]|\d+[.)])[ \t]+(\[[ xX]\][ \t]+)?"#)
    private static let codeSpan = pattern(#"(`+)(.+?)(\1)"#)
    private static let link = pattern(#"(!?\[)([^\]\n]*)(\]\([^)\n]*\))"#)
    private static let url = pattern(#"<https?://[^>\s]+>|(?<![(\w])https?://[^\s)>]+"#)
    private static let bold = pattern(#"(\*\*|__)(?=\S)(.+?)(?<=\S)(\1)"#)
    private static let italicStar = pattern(#"(?<![*\w])\*(?![*\s]).*?(?<![*\s])\*(?![*\w])"#)
    private static let italicUnderscore = pattern(#"(?<![_\w])_(?![_\s]).*?(?<![_\s])_(?![_\w])"#)
    private static let strike = pattern(#"(~~)(?=\S)(.+?)(?<=\S)(~~)"#)
}
