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
    var onScroll: ((EditorPane) -> Void)?

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
        // Lines are colored when TextKit lays them out, except while the whole text is laid out
        // in one go; then they are colored when they come into view.
        layoutManager.renderingAttributesValidator = { [weak self] layoutManager, fragment in
            guard let self, !isLayingOutEverything else { return }
            color(fragment, in: layoutManager)
            coloredFragments.add(fragment)
        }
        layoutManager.textContainer = textContainer

        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: textContainer)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        // Joined to the text only now: placing the text view in the scroll view sizes it, and
        // with the text already there, TextKit would lay out all of it at once.
        document.contentStorage.addTextLayoutManager(layoutManager)
        if document.contentStorage.primaryTextLayoutManager == nil {
            document.contentStorage.primaryTextLayoutManager = layoutManager
        }
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
        textView.onLiveResizeEnd = { [weak self] in self?.scheduleFullLayout() }
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

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        self.scrollView = scrollView

        ruler = LineNumberRuler(textView: textView, lineIndex: document.lineIndex)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        updateRuler()
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
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.postsFrameChangedNotifications = true
        observers = [
            // The insets depend on the size of the window.
            center.addObserver(forName: NSView.frameDidChangeNotification, object: scrollView, queue: .main) { [weak self] _ in
                self?.updateInsets()
            },
            // Paragraphs coming into view get their colors.
            center.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
                guard let self else { return }
                colorVisibleFragments()
                onScroll?(self)
            },
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

    override func viewDidAppear() {
        super.viewDidAppear()
        updateInsets()
        scheduleFullLayout()
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
        updateRuler()
        if state.showsInvisibles != invisibles.showsInvisibles {
            toggleInvisibles(nil)
        }
        let length = document.textStorage.length
        let location = min(max(state.selectionLocation, 0), length)
        textView.setSelectedRange(NSRange(location: location, length: min(max(state.selectionLength, 0), length - location)))
        scroll(toOffset: min(max(state.topOffset, 0), length))
        scheduleFullLayout()
    }

    /// The offset of the first line visible at the top.
    var topOffset: Int { textView.visibleTopOffset() ?? 0 }

    /// Scrolls so that the line at the offset is the first one visible. TextKit lays out only
    /// around the visible part and estimates the rest; relocating the viewport lays out from the
    /// line on and gives the matching scroll position.
    func scroll(toOffset offset: Int) {
        guard let content = layoutManager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: offset)
        else { return }
        let viewport = layoutManager.textViewportLayoutController
        if offset > 0 { textView.approach(offset) }
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

    private var lastTypewriterMode = Preferences.typewriterModeValue

    private func preferencesDidChange() {
        textView.highlightsCurrentLine = Preferences.highlightsCurrentLineValue
        if Preferences.focusModeValue != lastFocusMode {
            lastFocusMode = Preferences.focusModeValue
            focusedFragment = nil
            coloredFragments.removeAllObjects()
            colorVisibleFragments()
            updateFocusedFragment()
        }
        if Preferences.typewriterModeValue != lastTypewriterMode {
            lastTypewriterMode = Preferences.typewriterModeValue
            updateInsets()
        }
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
        scheduleFullLayout()
    }

    /// While the divider of a split view is dragged, the pane is in a live resize, in which
    /// TextKit waits with wrapping the lines anew until the mouse is released. The visible lines
    /// are wrapped right away instead.
    func rewrapAfterResize() {
        guard wrapsLines, textView.inLiveResize || scrollView.inLiveResize else { return }
        // Only the width changes; TextKit itself discards just the paragraphs that wrap
        // differently. Discarding the visible ones by hand made them flicker. The container
        // may already have followed the text view; then the layout is only due.
        let width = scrollView.contentSize.width
        if abs(textContainer.size.width - width) > 0.5 {
            textContainer.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.textViewportLayoutController.layoutViewport()
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
        scheduleFullLayout()
    }

    // MARK: - Coloring

    /// Colors one paragraph, that is one line, from the tokens of its language.
    private func color(_ fragment: NSTextLayoutFragment, in layoutManager: NSTextLayoutManager) {
        guard let content = layoutManager.textContentManager else { return }
        let range = fragment.rangeInElement
        layoutManager.removeRenderingAttribute(.foregroundColor, for: range)
        layoutManager.removeRenderingAttribute(.underlineStyle, for: range)
        defer {
            if isFaded(fragment, in: content) {
                layoutManager.addRenderingAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, for: range)
            }
        }
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
        // TextKit asks for colors only when it lays a paragraph out anew. Laying out again would
        // bring back its estimated heights, so the paragraphs are only marked: the visible ones
        // are colored now, the others when they come into view.
        let line = max(line, 1)
        guard line <= document.lineIndex.lineCount, let content = layoutManager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: document.lineIndex.start(ofLine: line))
        else { return }
        for case let fragment as NSTextLayoutFragment in coloredFragments.allObjects
        where fragment.rangeInElement.endLocation.compare(start) == .orderedDescending {
            coloredFragments.remove(fragment)
        }
        colorVisibleFragments()
    }

    /// The paragraphs a TextKit fragment at a time that have their colors; the others are colored
    /// when they come into view. Weak, so fragments TextKit discards drop out by themselves.
    private let coloredFragments = NSHashTable<NSTextLayoutFragment>.weakObjects()

    /// Colors the visible paragraphs that are not colored yet.
    private func colorVisibleFragments() {
        guard let content = layoutManager.textContentManager else { return }
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin
        // Nothing laid out there yet: TextKit colors the lines itself as it lays them out.
        guard let start = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: visible.minY - origin.y))?.rangeInElement.location
        else { return }
        var colored = false
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            if fragment.layoutFragmentFrame.minY + origin.y > visible.maxY { return false }
            if !coloredFragments.contains(fragment) {
                color(fragment, in: layoutManager)
                coloredFragments.add(fragment)
                colored = true
            }
            return true
        }
        if colored { textView.redrawFragments() }
    }

    /// Marks the bracket next to the insertion point and its partner.
    private func updateBrackets() {
        let pairs = document.language?.brackets ?? [("(", ")"), ("[", "]"), ("{", "}")]
        textView.bracketRanges = textView.matchingBrackets(pairs: pairs)
    }

    // MARK: - Selection

    /// The document's own undo manager, also where the pane is not in its document's window.
    func undoManager(for view: NSTextView) -> UndoManager? {
        document.undoManager
    }

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
        updateFocusedFragment()
        if Preferences.typewriterModeValue {
            // After TextKit has finished with the edit or movement that changed the selection.
            DispatchQueue.main.async { [weak self] in self?.centerInsertionPoint() }
        }
    }

    // MARK: - Writing modes

    /// The distraction-free mode as far as the pane is concerned: a column of text of this width
    /// without line numbers, always wrapped; nil outside the mode. Set by the editor.
    var distractionFreeColumn: CGFloat? {
        didSet {
            guard distractionFreeColumn != oldValue else { return }
            if distractionFreeColumn != nil, oldValue == nil {
                wrappedBeforeFocus = wrapsLines
                if !wrapsLines { wrapsLines = true; applyWrapping() }
            } else if distractionFreeColumn == nil, let wrapped = wrappedBeforeFocus {
                wrappedBeforeFocus = nil
                if wrapped != wrapsLines { wrapsLines = wrapped; applyWrapping() }
            }
            updateRuler()
            textColumnWidth = distractionFreeColumn
        }
    }
    private var wrappedBeforeFocus: Bool?

    private func updateRuler() {
        scrollView.rulersVisible = showsLineNumbers && distractionFreeColumn == nil
    }

    /// The focus mode: everything but the paragraph with the insertion point fades, in every
    /// window, with or without the distraction-free mode.
    private var lastFocusMode = Preferences.focusModeValue

    /// The paragraph with the insertion point, the one left strong in the focus mode.
    private weak var focusedFragment: NSTextLayoutFragment?

    private func isFaded(_ fragment: NSTextLayoutFragment, in content: NSTextContentManager) -> Bool {
        guard Preferences.focusModeValue else { return false }
        let caret = textView.selectedRange().location
        let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let end = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.endLocation)
        let isLast = fragment.rangeInElement.endLocation.compare(content.documentRange.endLocation) != .orderedAscending
        return !(caret >= start && (caret < end || (isLast && caret == end)))
    }

    /// When the insertion point moves to another paragraph, the old and the new one are colored anew.
    private func updateFocusedFragment() {
        guard Preferences.focusModeValue, let content = layoutManager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: textView.selectedRange().location)
        else { return }
        let current = layoutManager.textLayoutFragment(for: location)
        guard current !== focusedFragment else { return }
        if let old = focusedFragment { coloredFragments.remove(old) }
        if let current { coloredFragments.remove(current) }
        focusedFragment = current
        colorVisibleFragments()
    }

    /// The width of the text column in the distraction-free mode, nil otherwise; set by the editor.
    var textColumnWidth: CGFloat? {
        didSet { if textColumnWidth != oldValue { updateInsets() } }
    }

    /// The space around the text: in the typewriter mode half a window above and below, so
    /// that the first and last lines can stand in the middle too; in the distraction-free mode
    /// as much at the sides as leaves a column of the chosen width.
    func updateInsets() {
        guard let scrollView else { return }
        let size = scrollView.contentSize
        let lineHeight = EditorStyle.lineHeightPoints(font: textView.font ?? Preferences.font, multiple: Preferences.lineHeightValue)
        let vertical = Preferences.typewriterModeValue ? max((size.height - lineHeight) / 2, 6) : 6
        let horizontal = textColumnWidth.map { max((size.width - $0) / 2, 4) } ?? 4
        let inset = NSSize(width: horizontal.rounded(), height: vertical.rounded())
        guard inset != textView.textContainerInset else { return }
        let widthChanged = inset.width != textView.textContainerInset.width
        keepingTopLine {
            textView.textContainerInset = inset
            if wrapsLines {
                textContainer.size = NSSize(width: max(size.width - 2 * inset.width, 50), height: CGFloat.greatestFiniteMagnitude)
            }
        }
        if widthChanged { scheduleFullLayout() }
        if Preferences.typewriterModeValue { centerInsertionPoint() }
    }

    /// The typewriter mode: the line with the insertion point stays in the middle of the window.
    func centerInsertionPoint() {
        guard Preferences.typewriterModeValue, view.window != nil else { return }
        let caret = textView.caretRect(at: textView.selectedRange().upperBound)
        guard caret.height > 0 else { return }
        let clip = scrollView.contentView
        let maxY = max(textView.frame.height - clip.bounds.height, 0)
        let y = (caret.midY - clip.bounds.height / 2).clamped(to: 0...maxY)
        guard abs(y - clip.bounds.minY) > 0.5 else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: - NSTextLayoutManagerDelegate

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = InvisiblesLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.options = invisibles
        if !lineFillers.isEmpty, let content = textLayoutManager.textContentManager, let range = textElement.elementRange {
            let line = document.lineIndex.lineNumber(at: content.offset(from: content.documentRange.location, to: range.location))
            fragment.extraHeight = lineFillers[line] ?? 0
        }
        return fragment
    }

    // MARK: - Comparison

    /// Room below lines (numbered from 1) for lines the other side of a comparison has and this
    /// one has not; set by the comparison.
    var lineFillers: [Int: CGFloat] = [:] {
        didSet {
            guard lineFillers != oldValue else { return }
            let changed = Set(lineFillers.keys).union(oldValue.keys).filter { lineFillers[$0] != oldValue[$0] }
            guard let content = layoutManager.textContentManager else { return }
            for line in changed where line >= 1 && line <= document.lineIndex.lineCount {
                let start = document.lineIndex.start(ofLine: line)
                let end = line < document.lineIndex.lineCount ? document.lineIndex.start(ofLine: line + 1) : document.textStorage.length
                if let from = content.location(content.documentRange.location, offsetBy: start),
                   let to = content.location(from, offsetBy: max(end - start, 0)),
                   let range = NSTextRange(location: from, end: to) {
                    // TextKit keeps the fragments it has and only lays them out again, so the
                    // room is set on them as well as on the ones still to come.
                    if let fragment = layoutManager.textLayoutFragment(for: from) as? InvisiblesLayoutFragment {
                        fragment.extraHeight = lineFillers[line] ?? 0
                    }
                    layoutManager.invalidateLayout(for: range)
                }
            }
            scheduleFullLayout()
            textView.needsDisplay = true
            ruler.needsDisplay = true
        }
    }

    /// The colors of the comparison: line backgrounds by line (from 1), all other lines, the room
    /// below lines, and the characters that differ within changed lines.
    struct DiffMarks {
        var lineColors: [Int: NSColor] = [:]
        var equalColor: NSColor?
        var fillerColor = NSColor.clear
        var characters: [NSRange] = []
        var characterColor = NSColor.clear
    }

    var diffMarks: DiffMarks? {
        didSet {
            textView.extraBackgrounds = diffMarks == nil ? nil : { [weak self] rect in self?.diffBackgrounds(in: rect) ?? [] }
            textView.needsDisplay = true
        }
    }

    private func diffBackgrounds(in rect: NSRect) -> [(rect: NSRect, color: NSColor)] {
        guard let marks = diffMarks, let content = layoutManager.textContentManager else { return [] }
        var result: [(rect: NSRect, color: NSColor)] = []
        let origin = textView.textContainerOrigin
        let width = textView.bounds.width
        if textView.extraTopSpace > 0 {
            result.append((NSRect(x: 0, y: origin.y - textView.extraTopSpace, width: width, height: textView.extraTopSpace), marks.fillerColor))
        }
        let start = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: max(rect.minY - origin.y, 0)))?.rangeInElement.location
            ?? content.documentRange.location
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY + origin.y > rect.maxY { return false }
            let extra = (fragment as? InvisiblesLayoutFragment)?.extraHeight ?? 0
            let line = document.lineIndex.lineNumber(at: content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location))
            let textHeight = frame.height - extra
            if let color = marks.lineColors[line] ?? marks.equalColor {
                result.append((NSRect(x: 0, y: frame.minY + origin.y, width: width, height: textHeight), color))
            }
            if extra > 0 {
                result.append((NSRect(x: 0, y: frame.minY + origin.y + textHeight, width: width, height: extra), marks.fillerColor))
            }
            return true
        }
        for range in marks.characters {
            for frame in textView.segmentFrames(of: range) where frame.intersects(rect) {
                result.append((frame, marks.characterColor))
            }
        }
        return result
    }

    // MARK: - Folding

    /// Lays the text out again after folding. The line at the top stays where it is.
    // MARK: - Laying out the whole text

    /// TextKit 2 lays out only what is visible and estimates the height of the rest, so the
    /// scroller jumped while scrolling through long texts as the estimate changed. The whole
    /// text is therefore laid out in one go, after opening and after changes that lay out
    /// everything anew. Without coloring that takes about a quarter of a second for 5 MB;
    /// colors follow when the paragraphs come into view.
    private var isLayingOutEverything = false
    private var fullLayoutScheduled = false

    /// Beyond this many lines the text is left to TextKit's estimates: laying out costs about
    /// 20 µs a line, and the whole text is laid out in one go, so at most about a second.
    private static let fullLayoutLineLimit = 50_000
    /// A few very long lines can be as costly.
    private static let fullLayoutLimit = 20_000_000

    func scheduleFullLayout() {
        guard !fullLayoutScheduled else { return }
        fullLayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            fullLayoutScheduled = false
            layOutEverything()
        }
    }

    private func layOutEverything() {
        guard view.window != nil, document.lineIndex.lineCount <= Self.fullLayoutLineLimit,
              document.textStorage.length <= Self.fullLayoutLimit
        else { return }
        keepingTopLine {
            isLayingOutEverything = true
            layoutManager.ensureLayout(for: layoutManager.documentRange)
            isLayingOutEverything = false
        }
        colorVisibleFragments()
    }

    private func foldsDidChange() {
        keepingTopLine {
            layoutManager.invalidateLayout(for: layoutManager.documentRange)
            textView.needsLayout = true
        }
        textView.needsDisplay = true
        ruler.needsDisplay = true
        scheduleFullLayout()
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
        updateRuler()
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
