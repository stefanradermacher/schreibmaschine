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
        layoutManager.textContainer = textContainer
        document.contentStorage.addTextLayoutManager(layoutManager)
        document.contentStorage.primaryTextLayoutManager = layoutManager

        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: textContainer)
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
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

        let container = NSView()
        for view in [scrollView, statusBar!] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyFont()
        applyWrapping()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        updatePosition()

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.preferencesDidChange()
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
        ]
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Applying settings

    private var lastFont: NSFont?
    private var lastTabWidth = 0

    private func preferencesDidChange() {
        textView.highlightsCurrentLine = Preferences.highlightsCurrentLineValue
        let font = currentFont
        if font != lastFont || Preferences.tabWidthValue != lastTabWidth {
            applyFont()
        }
    }

    private var currentFont: NSFont {
        let base = Preferences.font
        return NSFont(descriptor: base.fontDescriptor, size: (base.pointSize + zoom).clamped(to: 6...96)) ?? base
    }

    private func applyFont() {
        let font = currentFont
        lastFont = font
        lastTabWidth = Preferences.tabWidthValue
        let attributes = EditorStyle.attributes(font: font)
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
        ruler.needsDisplay = true
    }

    // MARK: - NSTextLayoutManagerDelegate

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = InvisiblesLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.options = invisibles
        return fragment
    }

    // MARK: - View menu

    @objc func toggleLineNumbers(_ sender: Any?) {
        showsLineNumbers.toggle()
        scrollView.rulersVisible = showsLineNumbers
    }

    @objc func toggleWrapping(_ sender: Any?) {
        wrapsLines.toggle()
        applyWrapping()
    }

    @objc func toggleInvisibles(_ sender: Any?) {
        invisibles.showsInvisibles.toggle()
        // The fragments read the option when drawing; they only need to draw again.
        layoutManager.invalidateLayout(for: layoutManager.documentRange)
        textView.needsDisplay = true
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(zoom + 1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(zoom - 1) }
    @objc func resetZoom(_ sender: Any?) { setZoom(0) }

    private func setZoom(_ value: CGFloat) {
        let base = Preferences.font.pointSize
        zoom = (base + value).clamped(to: 6...96) - base
        applyFont()
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
