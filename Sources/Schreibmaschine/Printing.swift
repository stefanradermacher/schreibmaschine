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

/// The options of the print dialog, kept for next time.
enum PrintOptions {
    static let fontSize = "printFontSize"
    static let syntaxColors = "printSyntaxColors"
    static let lineNumbers = "printLineNumbers"
    static let headerAndFooter = "printHeaderAndFooter"
    static let headerShowsPath = "printHeaderShowsPath"
    static let markdownTypeset = "printMarkdownTypeset"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            fontSize: 10.0,
            syntaxColors: true,
            lineNumbers: true,
            headerAndFooter: true,
            headerShowsPath: false,
            markdownTypeset: false,
        ])
    }

    static var defaults: UserDefaults { .standard }
}

extension TextDocument {
    /// The print operation: the text in its own view, laid out for paper, with the options of
    /// the Schreibmaschine section of the print dialog.
    func makePrintOperation(printSettings: [NSPrintInfo.AttributeKey: Any]) -> NSPrintOperation {
        PrintOptions.registerDefaults()
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        // The view draws its own header and footer.
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = false
        info.topMargin = max(info.topMargin, 54)
        info.bottomMargin = max(info.bottomMargin, 54)

        let selection = editor?.textView.selectedRange() ?? NSRange(location: 0, length: 0)
        let view = PrintTextView(document: self, selection: selection)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = displayName
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        let panel = operation.printPanel
        panel.options.formUnion([.showsPaperSize, .showsOrientation, .showsScaling, .showsPreview, .showsCopies, .showsPageRange])
        if selection.length > 0 { panel.options.insert(.showsPrintSelection) }
        panel.addAccessoryController(PrintAccessoryController(isMarkdown: language?.id == "markdown"))
        return operation
    }
}

// MARK: - The view that is printed

/// The text as printed: wrapped to the width of the paper, in light colors, with line numbers
/// in a column on the left and a header and footer in the margins. It is laid out anew whenever
/// the options change, so the preview in the dialog follows them.
final class PrintTextView: NSTextView {
    private let document: TextDocument
    private let selection: NSRange
    /// Where each line of the printed text starts, and the number of its first line.
    private var lineStarts: [Int] = [0]
    private var firstLineNumber = 1
    private var gutterWidth: CGFloat = 0
    private var numberAttributes: [NSAttributedString.Key: Any] = [:]
    private var pageRects: [NSRect] = []
    private var date = Date()

    init(document: TextDocument, selection: NSRange) {
        self.document = document
        self.selection = selection
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = GutterTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)
        isEditable = false
        isSelectable = false
        drawsBackground = false
        isVerticallyResizable = true
        appearance = NSAppearance(named: .aqua)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var printInfo: NSPrintInfo { NSPrintOperation.current?.printInfo ?? document.printInfo }

    /// The size of the area for text on a page, in the coordinates of this view.
    private var pageContentSize: NSSize {
        let info = printInfo
        let scale = max((info.dictionary()[NSPrintInfo.AttributeKey.scalingFactor] as? CGFloat) ?? 1, 0.1)
        return NSSize(width: (info.paperSize.width - info.leftMargin - info.rightMargin) / scale,
                      height: (info.paperSize.height - info.topMargin - info.bottomMargin) / scale)
    }

    // MARK: Content

    private func rebuild() {
        let defaults = PrintOptions.defaults
        let full = document.textStorage.string as NSString
        let printsSelection = printInfo.isSelectionOnly && selection.length > 0
        let range = printsSelection ? selection : NSRange(location: 0, length: full.length)
        let text = full.substring(with: range)
        let size = CGFloat(defaults.double(forKey: PrintOptions.fontSize)).clamped(to: 6...36)
        let editorFont = Preferences.font
        let font = NSFont(descriptor: editorFont.fontDescriptor, size: size) ?? editorFont
        var base = EditorStyle.attributes(font: font, tabWidth: document.indentation.width)
        base[.foregroundColor] = NSColor.black

        let isMarkdown = document.language?.id == "markdown"
        let typeset = isMarkdown && defaults.bool(forKey: PrintOptions.markdownTypeset)
        let content: NSAttributedString
        if typeset {
            content = Self.typesetMarkdown(text, size: size)
        } else if isMarkdown && MarkdownStyler.isEnabled {
            content = MarkdownStyler.styled(text, base: base, lineHeight: Preferences.lineHeightValue)
        } else {
            let colored = NSMutableAttributedString(string: text, attributes: base)
            if defaults.bool(forKey: PrintOptions.syntaxColors) { color(colored, from: range) }
            content = colored
        }
        textStorage?.setAttributedString(content)

        // Line numbers count as in the document, also when only the selection is printed.
        let numbers = !typeset && defaults.bool(forKey: PrintOptions.lineNumbers)
        firstLineNumber = document.lineIndex.lineNumber(at: range.location)
        lineStarts = [0]
        let printed = text as NSString
        var index = 0
        while index < printed.length {
            let line = printed.lineRange(for: NSRange(location: index, length: 0))
            if line.upperBound < printed.length { lineStarts.append(line.upperBound) }
            index = line.upperBound
        }
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: max(size - 2, 6), weight: .regular)
        numberAttributes = [.font: numberFont, .foregroundColor: NSColor(white: 0.55, alpha: 1)]
        let widest = String(firstLineNumber + lineStarts.count - 1) as NSString
        gutterWidth = numbers ? (widest.size(withAttributes: numberAttributes).width + size * 1.5).rounded(.up) : 0
        textContainerInset = NSSize(width: 0, height: 0)
        // The numbers stand in a column left of the text, inside the printed area.
        (textContainer as? GutterTextContainer)?.leftInset = gutterWidth
        textContainer?.size = NSSize(width: pageContentSize.width, height: .greatestFiniteMagnitude)
        setFrameSize(NSSize(width: pageContentSize.width, height: 100))
        if let layoutManager, let container = textContainer {
            layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0), actualCharacterRange: nil)
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container)
            setFrameSize(NSSize(width: pageContentSize.width, height: max(used.maxY, 1)))
        }
        paginate()
    }

    /// Syntax colors from the document's highlighter, line by line.
    private func color(_ text: NSMutableAttributedString, from range: NSRange) {
        guard document.language != nil else { return }
        let first = document.lineIndex.lineNumber(at: range.location)
        let last = document.lineIndex.lineNumber(at: max(range.upperBound - 1, range.location))
        for line in first...last {
            for token in document.highlighter.tokens(forLine: line) {
                let clipped = NSIntersectionRange(token.range, range)
                guard clipped.length > 0 else { continue }
                let local = NSRange(location: clipped.location - range.location, length: clipped.length)
                text.addAttribute(.foregroundColor, value: token.scope.color, range: local)
            }
        }
    }

    /// Markdown set like the preview, through the HTML of the preview.
    private static func typesetMarkdown(_ text: String, size: CGFloat) -> NSAttributedString {
        let body = MarkdownRenderer.html(from: text)
        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, "Helvetica Neue", sans-serif; font-size: \(size + 1)pt; line-height: 1.45; color: #1d1d1f; }
        h1 { font-size: 1.8em; } h2 { font-size: 1.4em; } h3 { font-size: 1.2em; } h4, h5, h6 { font-size: 1em; }
        h1, h2, h3, h4, h5, h6 { margin: 1em 0 0.4em; }
        p, ul, ol, pre, blockquote, table { margin: 0 0 0.7em; }
        code, pre { font-family: "SF Mono", Menlo, monospace; font-size: 0.9em; }
        pre { background: #f2f2f5; padding: 0.5em; }
        blockquote { color: #6e6e73; margin-left: 1em; font-style: italic; }
        a { color: #3f6fb4; text-decoration: none; }
        table { border-collapse: collapse; } th, td { border: 1px solid #d2d2d7; padding: 2pt 6pt; } th { background: #f2f2f5; }
        hr { border: 0; border-top: 1px solid #d2d2d7; }
        </style></head><body>\(body)</body></html>
        """
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let data = html.data(using: .utf8),
              let result = try? NSAttributedString(data: data, options: options, documentAttributes: nil)
        else { return NSAttributedString(string: text) }
        return result
    }

    // MARK: Pages

    /// Pages end between lines, never through one.
    private func paginate() {
        let height = pageContentSize.height
        var rects: [NSRect] = []
        var top: CGFloat = 0
        if let layoutManager, let container = textContainer {
            let glyphs = layoutManager.glyphRange(for: container)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                if rect.maxY - top > height, rect.minY > top {
                    rects.append(NSRect(x: 0, y: top, width: self.bounds.width, height: rect.minY - top))
                    top = rect.minY
                }
            }
        }
        rects.append(NSRect(x: 0, y: top, width: bounds.width, height: max(bounds.height - top, 1)))
        pageRects = rects
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        date = Date()
        rebuild()
        range.pointee = NSRange(location: 1, length: pageRects.count)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        pageRects.indices.contains(page - 1) ? pageRects[page - 1] : .zero
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard gutterWidth > 0, let layoutManager, let container = textContainer, let storage = textStorage else { return }
        let text = storage.string as NSString
        let glyphs = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: container)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, glyphRange, _ in
            let character = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            // Only the first row of a line gets its number.
            guard character == 0 || (character <= text.length && text.character(at: character - 1) == 0x0A) else { return }
            let index = self.lineIndex(of: character)
            let number = String(self.firstLineNumber + index) as NSString
            let size = number.size(withAttributes: self.numberAttributes)
            let baseline = layoutManager.location(forGlyphAt: glyphRange.location).y
            let font = self.numberAttributes[.font] as? NSFont
            let y = rect.minY + baseline - (font?.ascender ?? size.height)
            number.draw(at: NSPoint(x: self.gutterWidth - size.width - size.height * 0.8, y: y), withAttributes: self.numberAttributes)
        }
    }

    private func lineIndex(of character: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle] <= character { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Header and footer in the margins: the file's name or path and the date above, the page
    /// below.
    override func drawPageBorder(with borderSize: NSSize) {
        guard PrintOptions.defaults.bool(forKey: PrintOptions.headerAndFooter), let operation = NSPrintOperation.current else { return }
        let info = operation.printInfo
        let font = NSFont.systemFont(ofSize: 8)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.4, alpha: 1)]
        let title: String
        if PrintOptions.defaults.bool(forKey: PrintOptions.headerShowsPath), let path = document.fileURL?.path {
            title = (path as NSString).abbreviatingWithTildeInPath
        } else {
            title = document.displayName
        }
        let dateText = date.formatted(date: .numeric, time: .shortened)
        let pageText = String(localized: "Seite \(operation.currentPage) von \(pageRects.count)")

        // AppKit has made the view as large as the sheet; the drawing goes from the bottom up
        // here, although the view is flipped, so text would come out upside down.
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let headerY = borderSize.height - info.topMargin / 2 - font.pointSize / 2
        let footerY = info.bottomMargin / 2 - font.pointSize / 2
        let width = borderSize.width - info.leftMargin - info.rightMargin
        let dateSize = (dateText as NSString).size(withAttributes: attributes)
        let titleRect = NSRect(x: info.leftMargin, y: headerY, width: width - dateSize.width - 12, height: font.pointSize * 1.5)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        var titleAttributes = attributes
        titleAttributes[.paragraphStyle] = style
        (title as NSString).draw(in: titleRect, withAttributes: titleAttributes)
        (dateText as NSString).draw(at: NSPoint(x: borderSize.width - info.rightMargin - dateSize.width, y: headerY), withAttributes: attributes)
        let pageSize = (pageText as NSString).size(withAttributes: attributes)
        (pageText as NSString).draw(at: NSPoint(x: (borderSize.width - pageSize.width) / 2, y: footerY), withAttributes: attributes)
    }
}

/// A text container whose lines start a little to the right, leaving room for line numbers.
private final class GutterTextContainer: NSTextContainer {
    var leftInset: CGFloat = 0

    override func lineFragmentRect(forProposedRect proposedRect: NSRect, at characterIndex: Int,
                                   writingDirection baseWritingDirection: NSWritingDirection,
                                   remaining remainingRect: UnsafeMutablePointer<NSRect>?) -> NSRect {
        var proposed = proposedRect
        proposed.origin.x += leftInset
        proposed.size.width = max(proposed.width - leftInset, 10)
        return super.lineFragmentRect(forProposedRect: proposed, at: characterIndex,
                                      writingDirection: baseWritingDirection, remaining: remainingRect)
    }
}

// MARK: - The section in the print dialog

/// Font size, colors, line numbers, header and footer, and for Markdown how it is set. Each
/// change goes to the settings and updates the preview.
final class PrintAccessoryController: NSViewController, NSPrintPanelAccessorizing {
    private let isMarkdown: Bool
    private let defaults = PrintOptions.defaults

    @objc dynamic var fontSize: Double = 10 { didSet { defaults.set(fontSize, forKey: PrintOptions.fontSize) } }
    @objc dynamic var syntaxColors = true { didSet { defaults.set(syntaxColors, forKey: PrintOptions.syntaxColors) } }
    @objc dynamic var lineNumbers = true { didSet { defaults.set(lineNumbers, forKey: PrintOptions.lineNumbers) } }
    @objc dynamic var headerAndFooter = true { didSet { defaults.set(headerAndFooter, forKey: PrintOptions.headerAndFooter) } }
    @objc dynamic var headerShowsPath = false { didSet { defaults.set(headerShowsPath, forKey: PrintOptions.headerShowsPath) } }
    @objc dynamic var markdownTypeset = false {
        didSet {
            defaults.set(markdownTypeset, forKey: PrintOptions.markdownTypeset)
            updateEnabling()
        }
    }

    private let sizeField = NSTextField()
    private let sizeStepper = NSStepper()
    private var colorBox: NSButton!
    private var numbersBox: NSButton!

    init(isMarkdown: Bool) {
        self.isMarkdown = isMarkdown
        super.init(nibName: nil, bundle: nil)
        title = "Schreibmaschine"
        fontSize = defaults.double(forKey: PrintOptions.fontSize)
        syntaxColors = defaults.bool(forKey: PrintOptions.syntaxColors)
        lineNumbers = defaults.bool(forKey: PrintOptions.lineNumbers)
        headerAndFooter = defaults.bool(forKey: PrintOptions.headerAndFooter)
        headerShowsPath = defaults.bool(forKey: PrintOptions.headerShowsPath)
        markdownTypeset = defaults.bool(forKey: PrintOptions.markdownTypeset)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        sizeField.formatter = { let f = NumberFormatter(); f.minimum = 6; f.maximum = 36; f.maximumFractionDigits = 1; return f }()
        sizeField.bind(.value, to: self, withKeyPath: "fontSize")
        sizeField.alignment = .right
        sizeField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        sizeStepper.minValue = 6
        sizeStepper.maxValue = 36
        sizeStepper.increment = 1
        sizeStepper.bind(.value, to: self, withKeyPath: "fontSize")
        let size = NSStackView(views: [sizeField, sizeStepper, NSTextField(labelWithString: "pt")])
        size.spacing = 4

        func checkbox(_ title: String, _ key: String) -> NSButton {
            let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            box.bind(.value, to: self, withKeyPath: key)
            return box
        }
        colorBox = checkbox(String(localized: "Syntaxfarben"), "syntaxColors")
        numbersBox = checkbox(String(localized: "Zeilennummern"), "lineNumbers")
        let header = checkbox(String(localized: "Kopf- und Fußzeile"), "headerAndFooter")
        let headerContent = NSPopUpButton()
        headerContent.addItems(withTitles: [String(localized: "Dateiname"), String(localized: "Dateipfad")])
        headerContent.bind(.selectedIndex, to: self, withKeyPath: "headerShowsPath", options: [.valueTransformer: BoolIndexTransformer()])
        headerContent.bind(.enabled, to: self, withKeyPath: "headerAndFooter")

        var rows: [[NSView]] = [
            [NSTextField(labelWithString: String(localized: "Schriftgröße:")), size],
            [NSGridCell.emptyContentView, colorBox],
            [NSGridCell.emptyContentView, numbersBox],
            [NSGridCell.emptyContentView, header],
            [NSTextField(labelWithString: String(localized: "Kopfzeile:")), headerContent],
        ]
        if isMarkdown {
            let markdown = NSPopUpButton()
            markdown.addItems(withTitles: [String(localized: "wie im Editor"), String(localized: "gesetzt wie in der Vorschau")])
            markdown.bind(.selectedIndex, to: self, withKeyPath: "markdownTypeset", options: [.valueTransformer: BoolIndexTransformer()])
            rows.append([NSTextField(labelWithString: String(localized: "Markdown:")), markdown])
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        let container = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
            grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
        // The print panel takes the accessory at the size of its frame.
        container.frame = NSRect(origin: .zero, size: container.fittingSize)
        preferredContentSize = container.fittingSize
        view = container
        updateEnabling()
    }

    /// Typeset Markdown has neither syntax colors nor line numbers.
    private func updateEnabling() {
        guard isViewLoaded else { return }
        colorBox.isEnabled = !(isMarkdown && markdownTypeset)
        numbersBox.isEnabled = !(isMarkdown && markdownTypeset)
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> {
        ["fontSize", "syntaxColors", "lineNumbers", "headerAndFooter", "headerShowsPath", "markdownTypeset"]
    }

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        func item(_ name: String, _ value: String) -> [NSPrintPanel.AccessorySummaryKey: String] {
            [.itemName: name, .itemDescription: value]
        }
        let on = String(localized: "Ein"), off = String(localized: "Aus")
        var items = [
            item(String(localized: "Schriftgröße"), "\(fontSize.formatted()) pt"),
            item(String(localized: "Syntaxfarben"), syntaxColors ? on : off),
            item(String(localized: "Zeilennummern"), lineNumbers ? on : off),
            item(String(localized: "Kopf- und Fußzeile"), headerAndFooter ? on : off),
        ]
        if isMarkdown {
            items.append(item(String(localized: "Markdown"), markdownTypeset ? String(localized: "gesetzt wie in der Vorschau") : String(localized: "wie im Editor")))
        }
        return items
    }
}

/// false and true as the first and second item of a pop-up menu.
private final class BoolIndexTransformer: ValueTransformer {
    override class func transformedValueClass() -> AnyClass { NSNumber.self }
    override class func allowsReverseTransformation() -> Bool { true }
    override func transformedValue(_ value: Any?) -> Any? { ((value as? Bool) ?? false) ? 1 : 0 }
    override func reverseTransformedValue(_ value: Any?) -> Any? { ((value as? Int) ?? 0) == 1 }
}
