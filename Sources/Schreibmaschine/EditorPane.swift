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

/// One view of the text: text view, line numbers and its own layout. An editor shows one pane,
/// or two side by side or one above the other; all of them share the document's text.
///
/// Line numbers, wrapping and invisibles belong to the pane; font size, bookmarks and folds to
/// the editor or the document, because the text storage holds the font and the folds hide text
/// for every view.
final class EditorPane: NSViewController, NSTextViewDelegate, NSTextLayoutManagerDelegate, NSMenuItemValidation {
    let document: TextDocument
    let layoutManager = NSTextLayoutManager()
    private let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    private(set) var textView: EditorTextView!
    private(set) var scrollView: NSScrollView!
    private var ruler: LineNumberRuler!
    private let invisibles = InvisiblesLayoutFragment.Options()
    private var observers: [NSObjectProtocol] = []

    private(set) var showsLineNumbers = UserDefaults.standard.bool(forKey: Preferences.showsLineNumbers)
    private(set) var wrapsLines = UserDefaults.standard.bool(forKey: Preferences.wrapsLines)
    var showsInvisibles: Bool { invisibles.showsInvisibles }

    /// Called when the pane's text gets the keyboard focus, and when its selection changes.
    var onFocus: ((EditorPane) -> Void)?
    var onSelectionChange: ((EditorPane) -> Void)?

    init(document: TextDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
        invisibles.showsInvisibles = UserDefaults.standard.bool(forKey: Preferences.showsInvisibles)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        document.contentStorage.removeTextLayoutManager(layoutManager)
    }

    override func loadView() {
        layoutManager.delegate = self
        // Lines are colored when TextKit is about to show them.
        layoutManager.renderingAttributesValidator = { [weak self] layoutManager, fragment in
            self?.color(fragment, in: layoutManager)
        }
        layoutManager.textContainer = textContainer
        document.contentStorage.addTextLayoutManager(layoutManager)
        if document.contentStorage.primaryTextLayoutManager == nil {
            document.contentStorage.primaryTextLayoutManager = layoutManager
        }

        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: textContainer)
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFontPanel = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = EditorStyle.insertionPointColor
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.highlightsCurrentLine = Preferences.highlightsCurrentLineValue
        textView.indentation = { [weak document] in document?.indentation ?? .preferred }
        textView.language = { [weak document] in document?.language }
        textView.onFocus = { [weak self] in
            guard let self else { return }
            onFocus?(self)
        }
        textView.foldPlaceholders = { [weak document] in document?.folds.map { $0.location - 1 } ?? [] }
        textView.onClickFoldPlaceholder = { [weak document] location in
            guard let document else { return }
            document.unfold(headedBy: document.lineIndex.lineNumber(at: location))
        }
        self.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        self.scrollView = scrollView

        ruler = LineNumberRuler(textView: textView, lineIndex: document.lineIndex)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = showsLineNumbers
        ruler.bookmarkedLines = { [weak document] in document?.bookmarkedLines ?? [] }
        ruler.onClickLine = { [weak document] line in document?.toggleBookmark(atLine: line) }
        ruler.foldMark = { [weak document] line in
            guard let document else { return .none }
            if document.foldedHeads.contains(line) { return .folded }
            return document.isFoldHead(line) ? .open : .none
        }
        ruler.foldedHeads = { [weak document] in document?.foldedHeads ?? [] }
        ruler.onClickFold = { [weak self] line in self?.toggleFold(headedBy: line) }

        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyWrapping()
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.preferencesDidChange()
            },
            center.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: document.textStorage, queue: .main) { [weak self] _ in
                self?.ruler.updateThickness()
                self?.ruler.needsDisplay = true
            },
            center.addObserver(forName: TextDocument.coloringDidInvalidate, object: document, queue: .main) { [weak self] note in
                self?.recolor(fromLine: note.userInfo?["line"] as? Int ?? 1)
            },
            center.addObserver(forName: TextDocument.languageDidChange, object: document, queue: .main) { [weak self] _ in
                self?.recolor(fromLine: 1)
                self?.updateBrackets()
            },
            center.addObserver(forName: TextDocument.foldsDidChange, object: document, queue: .main) { [weak self] _ in
                self?.foldsDidChange()
            },
            center.addObserver(forName: TextDocument.bookmarksDidChange, object: document, queue: .main) { [weak self] _ in
                self?.ruler.needsDisplay = true
            },
        ]
    }

    // MARK: - State

    struct State: Codable, Equatable {
        var selectionLocation = 0
        var selectionLength = 0
        var topOffset = 0
        var wrapsLines: Bool
        var showsLineNumbers: Bool
        var showsInvisibles: Bool
    }

    var state: State {
        let selection = textView.selectedRange()
        return State(selectionLocation: selection.location, selectionLength: selection.length, topOffset: topOffset,
                     wrapsLines: wrapsLines, showsLineNumbers: showsLineNumbers, showsInvisibles: invisibles.showsInvisibles)
    }

    func apply(_ state: State) {
        if state.wrapsLines != wrapsLines {
            wrapsLines = state.wrapsLines
            applyWrapping()
        }
        showsLineNumbers = state.showsLineNumbers
        scrollView.rulersVisible = showsLineNumbers
        if state.showsInvisibles != invisibles.showsInvisibles {
            toggleInvisibles(nil)
        }
        let length = document.textStorage.length
        let location = min(max(state.selectionLocation, 0), length)
        textView.setSelectedRange(NSRange(location: location, length: min(max(state.selectionLength, 0), length - location)))
        scroll(toOffset: min(max(state.topOffset, 0), length))
    }

    /// The offset of the first line visible at the top.
    var topOffset: Int {
        guard let content = layoutManager.textContentManager,
              let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: textView.visibleRect.minY - textView.textContainerOrigin.y))
        else { return 0 }
        return content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
    }

    /// Scrolls so that the line at the offset is the first one visible. TextKit lays out only
    /// around the visible part and estimates the rest; relocating the viewport lays out from the
    /// line on and gives the matching scroll position.
    func scroll(toOffset offset: Int) {
        guard let content = layoutManager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: offset)
        else { return }
        let viewport = layoutManager.textViewportLayoutController
        let y = offset == 0 ? 0 : viewport.relocateViewport(to: location) + textView.textContainerOrigin.y
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        viewport.layoutViewport()
    }

    /// Changes that lay out the text anew keep the line at the top where it was.
    func keepingTopLine(_ change: () -> Void) {
        guard view.window != nil else { return change() }
        let top = topOffset
        change()
        textView.layoutSubtreeIfNeeded()
        scroll(toOffset: top)
    }

    // MARK: - Settings

    private var lastHighlightsSyntax = Preferences.highlightsSyntaxValue

    private func preferencesDidChange() {
        textView.highlightsCurrentLine = Preferences.highlightsCurrentLineValue
        if Preferences.highlightsSyntaxValue != lastHighlightsSyntax {
            lastHighlightsSyntax = Preferences.highlightsSyntaxValue
            recolor(fromLine: 1)
        }
    }

    /// The font is set on the shared text storage by the editor; the pane takes it for typing
    /// and the line numbers.
    func takeFont(_ font: NSFont, attributes: [NSAttributedString.Key: Any]) {
        textView.font = font
        textView.typingAttributes = attributes
        textView.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        ruler.font = NSFont.monospacedDigitSystemFont(ofSize: max(9, font.pointSize - 2), weight: .regular)
        ruler.needsDisplay = true
    }

    private func applyWrapping() {
        let contentSize = scrollView.contentSize
        if wrapsLines {
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textContainer.widthTracksTextView = true
            textView.frame.size.width = contentSize.width
            textContainer.size = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            textContainer.widthTracksTextView = false
            textContainer.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.invalidateLayout(for: layoutManager.documentRange)
        textView.needsLayout = true
        textView.needsDisplay = true
    }

    // MARK: - Coloring

    /// Colors one paragraph, that is one line, from the tokens of its language.
    private func color(_ fragment: NSTextLayoutFragment, in layoutManager: NSTextLayoutManager) {
        guard let content = layoutManager.textContentManager else { return }
        let range = fragment.rangeInElement
        layoutManager.removeRenderingAttribute(.foregroundColor, for: range)
        layoutManager.removeRenderingAttribute(.underlineStyle, for: range)
        guard Preferences.highlightsSyntaxValue, document.language != nil else { return }
        let start = content.offset(from: content.documentRange.location, to: range.location)
        let end = content.offset(from: content.documentRange.location, to: range.endLocation)
        let line = document.lineIndex.lineNumber(at: start)
        for token in document.highlighter.tokens(forLine: line) {
            let from = max(token.range.location, start), to = min(token.range.upperBound, end)
            guard from < to,
                  let tokenStart = content.location(content.documentRange.location, offsetBy: from),
                  let tokenEnd = content.location(tokenStart, offsetBy: to - from),
                  let tokenRange = NSTextRange(location: tokenStart, end: tokenEnd)
            else { continue }
            layoutManager.addRenderingAttribute(.foregroundColor, value: token.scope.color, for: tokenRange)
            if token.scope == .link {
                layoutManager.addRenderingAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, for: tokenRange)
            }
        }
    }

    /// After an edit or a change of language: the lines from `line` on are colored again when
    /// shown; the visible ones right away.
    private func recolor(fromLine line: Int) {
        // Edits are reported while TextKit is still processing them; its paragraphs are only
        // up to date afterwards. Several edits in a row are handled together.
        pendingRecolorLine = min(pendingRecolorLine ?? line, line)
        guard !recolorScheduled else { return }
        recolorScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            recolorScheduled = false
            let line = pendingRecolorLine ?? 1
            pendingRecolorLine = nil
            recolorNow(fromLine: line)
        }
    }

    private var recolorScheduled = false
    private var pendingRecolorLine: Int?

    private func recolorNow(fromLine line: Int) {
        guard line <= document.lineIndex.lineCount, let content = layoutManager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: document.lineIndex.start(ofLine: line)),
              let range = NSTextRange(location: start, end: content.documentRange.endLocation)
        else { return }
        // TextKit asks for colors only when it lays a paragraph out anew. The paragraphs on screen
        // are colored here directly; the ones below are laid out again when they come into view.
        let viewport = layoutManager.textViewportLayoutController.viewportRange
        let visibleEnd = viewport?.endLocation ?? content.documentRange.endLocation
        layoutManager.enumerateTextLayoutFragments(from: range.location, options: []) { fragment in
            guard fragment.rangeInElement.location.compare(visibleEnd) == .orderedAscending else { return false }
            color(fragment, in: layoutManager)
            return true
        }
        if visibleEnd.compare(content.documentRange.endLocation) == .orderedAscending,
           let below = NSTextRange(location: visibleEnd.compare(range.location) == .orderedDescending ? visibleEnd : range.location,
                                   end: content.documentRange.endLocation) {
            layoutManager.invalidateLayout(for: below)
        }
        textView.redrawFragments()
    }

    /// Marks the bracket next to the insertion point and its partner.
    private func updateBrackets() {
        let pairs = document.language?.brackets ?? [("(", ")"), ("[", "]"), ("{", "}")]
        textView.bracketRanges = textView.matchingBrackets(pairs: pairs)
    }

    // MARK: - Selection

    func textViewDidChangeSelection(_ notification: Notification) {
        // A selection in folded text, from searching or going to a line, opens the fold.
        if !document.folds.isEmpty {
            for range in textView.editingRanges where document.isFolded(range.location) || (range.length > 0 && document.isFolded(range.upperBound - 1)) {
                document.unfold(containing: range.location)
                document.unfold(containing: max(range.upperBound - 1, range.location))
            }
        }
        updateBrackets()
        ruler.needsDisplay = true
        onSelectionChange?(self)
    }

    // MARK: - NSTextLayoutManagerDelegate

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = InvisiblesLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.options = invisibles
        return fragment
    }

    // MARK: - Folding

    /// Lays the text out again after folding. The line at the top stays where it is.
    private func foldsDidChange() {
        keepingTopLine {
            layoutManager.invalidateLayout(for: layoutManager.documentRange)
            textView.needsLayout = true
        }
        textView.needsDisplay = true
        ruler.needsDisplay = true
    }

    private func toggleFold(headedBy line: Int) {
        if document.foldedHeads.contains(line) {
            document.unfold(headedBy: line)
        } else {
            foldAndKeepCaret(headedBy: line)
        }
    }

    /// Folds and moves an insertion point that would be hidden to the head line.
    private func foldAndKeepCaret(headedBy line: Int) {
        guard document.fold(headedBy: line) else { return NSSound.beep() }
        if document.isFolded(textView.selectedRange().location) {
            let end = FoldRegions.lineRange(line, in: document.textStorage.string as NSString, lineIndex: document.lineIndex).upperBound
            textView.setSelectedRange(NSRange(location: end, length: 0))
        }
    }

    /// ⌃⌘←: folds the innermost block around the insertion point, or the one its line heads.
    @objc func foldBlock(_ sender: Any?) {
        let line = caretLine
        var head = line
        while head >= 1 {
            if let region = document.foldRegion(headedBy: head), head == line || region.contains(line),
               !document.foldedHeads.contains(head) {
                return foldAndKeepCaret(headedBy: head)
            }
            head -= 1
        }
        NSSound.beep()
    }

    /// ⌃⌘→: opens the fold headed by the line of the insertion point, or the innermost around it.
    @objc func unfoldBlock(_ sender: Any?) {
        let line = caretLine
        let heads = document.foldedHeads
        if heads.contains(line) { return document.unfold(headedBy: line) }
        guard let head = heads.filter({ $0 < line && (document.foldRegion(headedBy: $0)?.contains(line) ?? false) }).max() else {
            return NSSound.beep()
        }
        document.unfold(headedBy: head)
    }

    /// Folds every block that is not inside another.
    @objc func foldAll(_ sender: Any?) {
        var ranges: [NSRange] = []
        var line = 1
        let count = document.lineIndex.lineCount
        while line <= count {
            if let region = document.foldRegion(headedBy: line) {
                ranges.append(document.characterRange(ofLines: region))
                line = region.upperBound + 1
            } else {
                line += 1
            }
        }
        guard !ranges.isEmpty else { return NSSound.beep() }
        document.setFolds(ranges)
        let caret = textView.selectedRange().location
        if let fold = ranges.first(where: { $0.location <= caret && caret < $0.upperBound }) {
            textView.setSelectedRange(NSRange(location: fold.location - 1, length: 0))
        }
    }

    @objc func unfoldAll(_ sender: Any?) {
        document.setFolds([])
    }

    // MARK: - Bookmarks

    private var caretLine: Int { document.lineIndex.lineNumber(at: textView.selectedRange().location) }

    @objc func toggleBookmark(_ sender: Any?) {
        document.toggleBookmark(atLine: caretLine)
    }

    @objc func nextBookmark(_ sender: Any?) {
        let lines = document.bookmarkedLines
        guard let line = lines.first(where: { $0 > caretLine }) ?? lines.first else { return NSSound.beep() }
        goToBookmark(line: line)
    }

    @objc func previousBookmark(_ sender: Any?) {
        let lines = document.bookmarkedLines
        guard let line = lines.last(where: { $0 < caretLine }) ?? lines.last else { return NSSound.beep() }
        goToBookmark(line: line)
    }

    @objc func removeAllBookmarks(_ sender: Any?) {
        document.setBookmarkedLines([])
        SessionStore.shared.setNeedsSave()
    }

    /// An entry of the bookmark list in the menu; the tag is the line.
    @objc func goToBookmark(_ sender: NSMenuItem) {
        goToBookmark(line: sender.tag)
    }

    private func goToBookmark(line: Int) {
        let range = NSRange(location: document.lineIndex.start(ofLine: line), length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.centerSelectionInVisibleArea(nil)
    }

    // MARK: - View menu

    @objc func toggleLineNumbers(_ sender: Any?) {
        showsLineNumbers.toggle()
        scrollView.rulersVisible = showsLineNumbers
    }

    @objc func toggleWrapping(_ sender: Any?) {
        keepingTopLine {
            wrapsLines.toggle()
            applyWrapping()
        }
    }

    @objc func toggleInvisibles(_ sender: Any?) {
        // The fragments read the option when drawing, so they only need to draw again.
        invisibles.showsInvisibles.toggle()
        textView.redrawFragments()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleLineNumbers(_:)):
            item.state = showsLineNumbers ? .on : .off
        case #selector(toggleWrapping(_:)):
            item.state = wrapsLines ? .on : .off
        case #selector(toggleInvisibles(_:)):
            item.state = invisibles.showsInvisibles ? .on : .off
        case #selector(unfoldAll(_:)):
            return !document.folds.isEmpty
        case #selector(nextBookmark(_:)), #selector(previousBookmark(_:)), #selector(removeAllBookmarks(_:)):
            return !document.bookmarks.isEmpty
        case #selector(toggleBookmark(_:)):
            item.title = document.bookmarkedLines.contains(caretLine)
                ? String(localized: "Lesezeichen entfernen") : String(localized: "Lesezeichen setzen")
        default:
            break
        }
        return true
    }
}
