import AppKit

/// One view of a document: the text with line numbers and the status bar.
///
/// Line numbers, wrapping, invisibles and zoom belong to the view; they start from the settings.
final class EditorViewController: NSViewController, NSTextViewDelegate, NSTextLayoutManagerDelegate, NSMenuItemValidation {
    let document: TextDocument
    private let layoutManager = NSTextLayoutManager()
    private let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    private(set) var textView: EditorTextView!
    private var scrollView: NSScrollView!
    private var ruler: LineNumberRuler!
    private var statusBar: StatusBar!
    private(set) var search: SearchController!
    private var textAtTop: NSLayoutConstraint!
    private let allDocumentsView = AllDocumentsSearchView()
    private var editorAtLeft: NSLayoutConstraint!
    private var editorBesideSidebar: NSLayoutConstraint!
    private var textBelowBar: NSLayoutConstraint!
    private let invisibles = InvisiblesLayoutFragment.Options()
    private var observers: [NSObjectProtocol] = []

    private(set) var showsLineNumbers = UserDefaults.standard.bool(forKey: Preferences.showsLineNumbers)
    private(set) var wrapsLines = UserDefaults.standard.bool(forKey: Preferences.wrapsLines)
    /// Change of the font size against the settings, in points.
    private var zoom: CGFloat = 0

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
        document.contentStorage.primaryTextLayoutManager = layoutManager

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

        statusBar = StatusBar(document: document)
        search = SearchController(textView: textView, layoutManager: layoutManager, document: document)
        textView.onCancel = { [weak self] in
            guard let search = self?.search, search.isVisible else { return false }
            search.close()
            return true
        }

        let container = NSView()   // the editor: find bar, text, status bar
        let bar = search.bar
        let marks = search.marksView
        for view in [bar, scrollView, statusBar!, marks] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        // The text starts below the find bar while it is shown, at the top otherwise.
        textBelowBar = scrollView.topAnchor.constraint(equalTo: bar.bottomAnchor)
        textAtTop = scrollView.topAnchor.constraint(equalTo: container.topAnchor)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textAtTop,
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            marks.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 2),
            marks.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -2),
            marks.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -1),
            marks.widthAnchor.constraint(equalToConstant: 7),
        ])
        search.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            textAtTop.isActive = !visible
            textBelowBar.isActive = visible
        }

        // The search in all documents shows its results in a sidebar on the left.
        let root = NSView()
        allDocumentsView.isHidden = true
        for view in [allDocumentsView, container] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        editorAtLeft = container.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        editorBesideSidebar = container.leadingAnchor.constraint(equalTo: allDocumentsView.trailingAnchor)
        NSLayoutConstraint.activate([
            allDocumentsView.topAnchor.constraint(equalTo: root.topAnchor),
            allDocumentsView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            allDocumentsView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            allDocumentsView.widthAnchor.constraint(equalToConstant: 300),
            editorAtLeft,
            container.topAnchor.constraint(equalTo: root.topAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyFont()
        applyWrapping()
        updateSidebar()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        updatePosition()

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.preferencesDidChange()
            },
            center.addObserver(forName: AllDocumentsSearch.didChange, object: nil, queue: .main) { [weak self] _ in
                self?.updateSidebar()
            },
            center.addObserver(forName: TextDocument.formatDidChange, object: document, queue: .main) { [weak self] _ in
                self?.statusBar.updateFormat()
            },
            center.addObserver(forName: TextDocument.textDidReload, object: document, queue: .main) { [weak self] _ in
                self?.applyFont()
                self?.textView.setSelectedRange(NSRange(location: 0, length: 0))
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
                self?.statusBar.updateFormat()
                self?.updateBrackets()
            },
            center.addObserver(forName: TextDocument.indentationDidChange, object: document, queue: .main) { [weak self] _ in
                self?.applyFont()
                self?.statusBar.updateFormat()
            },
        ]
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
        if let state = pendingViewState {
            pendingViewState = nil
            apply(state)
        }
        #if DEBUG
        // For looking at the find bar without a keyboard: -DebugFindBar find|replace|goto
        // and -DebugFindText <text>.
        if let mode = UserDefaults.standard.string(forKey: "DebugFindBar") {
            search.show(mode == "replace" ? .replace : mode == "goto" ? .goToLine : .find)
            if let text = UserDefaults.standard.string(forKey: "DebugFindText") {
                search.bar.setSearchText(text)
                search.findBarQueryDidChange(search.bar)
            }
        }
        #endif
    }

    // MARK: - View state

    /// Applied when the view first appears: the state the file was last shown with.
    var pendingViewState: ViewState?

    var viewState: ViewState {
        if let pendingViewState { return pendingViewState }
        let selection = textView.selectedRange()
        var topOffset = 0
        if let content = layoutManager.textContentManager,
           let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: textView.visibleRect.minY - textView.textContainerOrigin.y)) {
            topOffset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        }
        return ViewState(
            selectionLocation: selection.location, selectionLength: selection.length, topOffset: topOffset,
            wrapsLines: wrapsLines, showsLineNumbers: showsLineNumbers, showsInvisibles: invisibles.showsInvisibles,
            zoom: Double(zoom))
    }

    private func apply(_ state: ViewState) {
        if state.wrapsLines != wrapsLines {
            wrapsLines = state.wrapsLines
            applyWrapping()
        }
        showsLineNumbers = state.showsLineNumbers
        scrollView.rulersVisible = showsLineNumbers
        if state.showsInvisibles != invisibles.showsInvisibles {
            toggleInvisibles(nil)
        }
        if CGFloat(state.zoom) != zoom { setZoom(CGFloat(state.zoom)) }

        let length = document.textStorage.length
        let location = min(max(state.selectionLocation, 0), length)
        textView.setSelectedRange(NSRange(location: location, length: min(max(state.selectionLength, 0), length - location)))
        scroll(toOffset: min(max(state.topOffset, 0), length))
    }

    /// Scrolls so that the line at the offset is the first one visible. TextKit lays out only
    /// around the visible part and estimates the rest; relocating the viewport lays out from the
    /// line on and gives the matching scroll position.
    private func scroll(toOffset offset: Int) {
        guard let content = layoutManager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: offset)
        else { return }
        let viewport = layoutManager.textViewportLayoutController
        let y = offset == 0 ? 0 : viewport.relocateViewport(to: location) + textView.textContainerOrigin.y
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        viewport.layoutViewport()
    }

    // MARK: - Applying settings

    private var lastFont: NSFont?
    private var lastHighlightsSyntax = Preferences.highlightsSyntaxValue

    private func preferencesDidChange() {
        textView.highlightsCurrentLine = Preferences.highlightsCurrentLineValue
        if currentFont != lastFont {
            applyFont()
        }
        if Preferences.highlightsSyntaxValue != lastHighlightsSyntax {
            lastHighlightsSyntax = Preferences.highlightsSyntaxValue
            recolor(fromLine: 1)
        }
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

    private var currentFont: NSFont {
        let base = Preferences.font
        return NSFont(descriptor: base.fontDescriptor, size: (base.pointSize + zoom).clamped(to: 6...96)) ?? base
    }

    private func applyFont() {
        let font = currentFont
        lastFont = font
        let attributes = EditorStyle.attributes(font: font, tabWidth: document.indentation.width)
        let storage = document.textStorage
        storage.beginEditing()
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
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

    // MARK: - Status

    private func updatePosition() {
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let lineIndex = document.lineIndex
        let line = lineIndex.lineNumber(at: selection.location)
        let lineStart = lineIndex.start(ofLine: line)
        // Characters as the reader counts them, not UTF-16 units; long lines are counted in units.
        let prefix = NSRange(location: lineStart, length: selection.location - lineStart)
        let column = (prefix.length < 10_000 ? text.substring(with: prefix).count : prefix.length) + 1
        var selectedCharacters = 0
        var selectedLines = 0
        if selection.length > 0 {
            let selected = textView.selectedRanges.map(\.rangeValue)
            selectedCharacters = selected.reduce(0) { $0 + ($1.length < 100_000 ? text.substring(with: $1).count : $1.length) }
            let last = selection.upperBound - 1
            selectedLines = lineIndex.lineNumber(at: last) - line + 1
        }
        statusBar.updatePosition(line: line, column: column, selectedCharacters: selectedCharacters, selectedLines: selectedLines)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updatePosition()
        updateBrackets()
        ruler.needsDisplay = true
    }

    // MARK: - NSTextLayoutManagerDelegate

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = InvisiblesLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.options = invisibles
        return fragment
    }

    // MARK: - Find menu

    @objc func showFindBar(_ sender: Any?) { search.show(.find) }
    @objc func showReplaceBar(_ sender: Any?) { search.show(.replace) }
    @objc func showGoToLine(_ sender: Any?) { search.show(.goToLine) }
    @objc func findNextMatch(_ sender: Any?) { search.findNext(backwards: false) }
    @objc func findPreviousMatch(_ sender: Any?) { search.findNext(backwards: true) }
    @objc func selectAllMatches(_ sender: Any?) { search.selectAll() }
    @objc func useSelectionForFind(_ sender: Any?) { search.useSelection() }

    @objc func showAllDocumentsSearch(_ sender: Any?) {
        let selection = textView.selectedRange()
        var text: String?
        if selection.length > 0, selection.length < 2000 {
            text = (textView.string as NSString).substring(with: selection)
        } else if AllDocumentsSearch.shared.text.isEmpty {
            text = search.bar.searchField.stringValue.isEmpty ? SearchController.findPasteboardText : search.bar.searchField.stringValue
        }
        AllDocumentsSearch.shared.activate(with: text)
        allDocumentsView.focus()
    }

    private func updateSidebar() {
        let active = AllDocumentsSearch.shared.isActive
        guard allDocumentsView.isHidden == active else { return }
        allDocumentsView.isHidden = !active
        editorAtLeft.isActive = !active
        editorBesideSidebar.isActive = active
        if !active, view.window?.firstResponder is NSTextView, view.window?.firstResponder !== textView {
            view.window?.makeFirstResponder(textView)
        }
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

    @objc func zoomIn(_ sender: Any?) { setZoom(zoom + 1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(zoom - 1) }
    @objc func resetZoom(_ sender: Any?) { setZoom(0) }

    private func setZoom(_ value: CGFloat) {
        let base = Preferences.font.pointSize
        keepingTopLine {
            zoom = (base + value).clamped(to: 6...96) - base
            applyFont()
        }
    }

    /// Changes that lay out the text anew keep the line at the top where it was.
    private func keepingTopLine(_ change: () -> Void) {
        guard view.window != nil else { return change() }
        let top = viewState.topOffset
        change()
        textView.layoutSubtreeIfNeeded()
        scroll(toOffset: top)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleLineNumbers(_:)):
            item.state = showsLineNumbers ? .on : .off
        case #selector(toggleWrapping(_:)):
            item.state = wrapsLines ? .on : .off
        case #selector(toggleInvisibles(_:)):
            item.state = invisibles.showsInvisibles ? .on : .off
        case #selector(resetZoom(_:)):
            return zoom != 0
        default:
            break
        }
        return true
    }
}
