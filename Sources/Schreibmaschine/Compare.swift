import AppKit

/// One side of a comparison: a document, and how it is shown.
struct CompareSide {
    let document: TextDocument
    let title: String
    /// Not a file that can be changed: the clipboard or the saved version on disk.
    let isReadOnly: Bool
}

/// The window of a comparison. It can join the tabs of the document windows; it is not part of
/// the session, a comparison is started anew when needed.
final class CompareWindowController: NSWindowController, NSWindowDelegate {
    private let compare: CompareViewController

    init(left: CompareSide, right: CompareSide) {
        compare = CompareViewController(left: left, right: right)
        let window = NSWindow(contentViewController: compare)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1100, height: 760))
        window.title = String(localized: "\(left.title) ↔ \(right.title)")
        window.tabbingIdentifier = DocumentWindowController.tabbingIdentifier
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self
        Self.open.append(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Comparison windows keep themselves alive until they close.
    private static var open: [CompareWindowController] = []

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        compare.confirmClosing()
    }

    func windowWillClose(_ notification: Notification) {
        compare.tearDown()
        Self.open.removeAll { $0 === self }
    }
}

/// Two texts side by side: lines that belong together stand at the same height, with room
/// left where one side has lines the other has not. Changed, deleted and inserted lines are
/// tinted, the differing characters within changed lines more strongly. A strip in the middle
/// joins the blocks and takes a block over to the other side; a bar at the right shows all
/// differences of the whole text. Both sides are ordinary editors, the comparison follows
/// every change.
final class CompareViewController: NSViewController, NSMenuItemValidation {
    let left: CompareSide
    let right: CompareSide
    private let leftPane: EditorPane
    private let rightPane: EditorPane
    private let strip = CompareStrip()
    private let overview = CompareOverview()
    private let statusLabel = NSTextField(labelWithString: "")
    private let whitespaceToggle = NSButton(checkboxWithTitle: String(localized: "Leerraum ignorieren"), target: nil, action: nil)
    private let caseToggle = NSButton(checkboxWithTitle: String(localized: "Groß-/Kleinschreibung ignorieren"), target: nil, action: nil)
    private var observers: [NSObjectProtocol] = []
    private var diff: TextDiff?
    private var generation = 0
    private var isSyncingScroll = false
    /// The difference last jumped to, for "Difference 3 of 12".
    private var currentHunk: Int?

    init(left: CompareSide, right: CompareSide) {
        self.left = left
        self.right = right
        leftPane = EditorPane(document: left.document)
        rightPane = EditorPane(document: right.document)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let root = NSView()
        addChild(leftPane)
        addChild(rightPane)
        let leftHeader = header(left)
        let rightHeader = header(right)

        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        for toggle in [whitespaceToggle, caseToggle] {
            toggle.controlSize = .small
            toggle.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            toggle.target = self
            toggle.action = #selector(optionsChanged(_:))
        }
        let previous = NSButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: String(localized: "Voriger Unterschied"))!,
                                target: self, action: #selector(previousDifference(_:)))
        let next = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: String(localized: "Nächster Unterschied"))!,
                            target: self, action: #selector(nextDifference(_:)))
        for button in [previous, next] {
            button.isBordered = false
            button.controlSize = .small
        }
        previous.toolTip = String(localized: "Voriger Unterschied (⌃⌘↑)")
        next.toolTip = String(localized: "Nächster Unterschied (⌃⌘↓)")
        let bottom = NSStackView(views: [previous, next, statusLabel, NSView(), whitespaceToggle, caseToggle])
        bottom.spacing = 10
        bottom.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 10)
        let separator = NSBox()
        separator.boxType = .separator

        strip.compare = self
        overview.compare = self
        for view in [leftHeader, rightHeader, leftPane.view, strip, rightPane.view, overview, separator, bottom] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            leftHeader.topAnchor.constraint(equalTo: root.topAnchor),
            leftHeader.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            leftHeader.trailingAnchor.constraint(equalTo: leftPane.view.trailingAnchor),
            leftHeader.heightAnchor.constraint(equalToConstant: 26),
            rightHeader.topAnchor.constraint(equalTo: root.topAnchor),
            rightHeader.leadingAnchor.constraint(equalTo: rightPane.view.leadingAnchor),
            rightHeader.trailingAnchor.constraint(equalTo: rightPane.view.trailingAnchor),
            rightHeader.heightAnchor.constraint(equalToConstant: 26),

            leftPane.view.topAnchor.constraint(equalTo: leftHeader.bottomAnchor),
            leftPane.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            leftPane.view.bottomAnchor.constraint(equalTo: separator.topAnchor),
            strip.topAnchor.constraint(equalTo: leftPane.view.topAnchor),
            strip.bottomAnchor.constraint(equalTo: leftPane.view.bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: leftPane.view.trailingAnchor),
            strip.widthAnchor.constraint(equalToConstant: 34),
            rightPane.view.topAnchor.constraint(equalTo: leftPane.view.topAnchor),
            rightPane.view.bottomAnchor.constraint(equalTo: leftPane.view.bottomAnchor),
            rightPane.view.leadingAnchor.constraint(equalTo: strip.trailingAnchor),
            rightPane.view.widthAnchor.constraint(equalTo: leftPane.view.widthAnchor),
            overview.topAnchor.constraint(equalTo: leftPane.view.topAnchor),
            overview.bottomAnchor.constraint(equalTo: leftPane.view.bottomAnchor),
            overview.leadingAnchor.constraint(equalTo: rightPane.view.trailingAnchor),
            overview.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            overview.widthAnchor.constraint(equalToConstant: 12),

            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bottom.topAnchor.constraint(equalTo: separator.bottomAnchor),
            bottom.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 26),
        ])
        view = root
    }

    private func header(_ side: CompareSide) -> NSView {
        let label = NSTextField(labelWithString: side.title)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.toolTip = side.document.fileURL?.path
        let note = NSTextField(labelWithString: side.isReadOnly ? String(localized: "nur lesen") : "")
        note.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .tertiaryLabelColor
        let stack = NSStackView(views: [label, note, NSView()])
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return stack
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        for (pane, side) in [(leftPane, left), (rightPane, right)] {
            // Unwrapped, so every line has the same height and the sides can be aligned.
            pane.apply(EditorPane.State(wrapsLines: false, showsLineNumbers: true, showsInvisibles: false))
            let font = Preferences.font
            pane.takeFont(font, attributes: EditorStyle.attributes(font: font, tabWidth: side.document.indentation.width))
            pane.textView.isEditable = !side.isReadOnly
            pane.onScroll = { [weak self] pane in self?.scrolled(pane) }
            pane.textView.highlightsCurrentLine = false
        }
        let center = NotificationCenter.default
        for document in [left.document, right.document] {
            observers.append(center.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: document.textStorage, queue: .main) { [weak self] _ in
                guard document.textStorage.editedMask.contains(.editedCharacters) else { return }
                self?.scheduleComparison()
            })
        }
        compare()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(leftPane.textView)
        // Both sides start at the beginning, also of the lines.
        for pane in [leftPane, rightPane] {
            // The line numbers lie over the clip view, which leaves room for them with a
            // negative bounds origin; the smallest allowed origin is the beginning.
            let clip = pane.scrollView.contentView
            let start = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: -1_000_000, y: -1_000_000), size: clip.bounds.size)).origin
            clip.scroll(to: start)
            pane.scrollView.reflectScrolledClipView(pane.scrollView.contentView)
        }
    }

    func tearDown() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        generation += 1
    }

    // MARK: - Comparing

    private var options: TextDiff.Options {
        TextDiff.Options(ignoresWhitespace: whitespaceToggle.state == .on, ignoresCase: caseToggle.state == .on)
    }

    @objc private func optionsChanged(_ sender: Any?) { compare() }

    private var pending: DispatchWorkItem?

    private func scheduleComparison() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.compare() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Compares away from the main thread and shows the result when it is still current.
    private func compare() {
        generation += 1
        let generation = generation
        let leftText = left.document.textStorage.string, rightText = right.document.textStorage.string
        let options = options
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let diff = TextDiff(left: leftText, right: rightText, options: options)
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                self.show(diff)
            }
        }
    }

    /// The height of a line, measured on the first line as laid out; every line is that high,
    /// the text is not wrapped and the line height is fixed.
    private var lineHeight: CGFloat {
        let layoutManager = leftPane.layoutManager
        if let content = layoutManager.textContentManager,
           let fragment = layoutManager.textLayoutFragment(for: content.documentRange.location),
           let line = fragment.textLineFragments.first {
            return line.typographicBounds.height
        }
        return EditorStyle.lineHeightPoints(font: Preferences.font, multiple: Preferences.lineHeightValue)
    }

    private func show(_ diff: TextDiff) {
        self.diff = diff
        let height = lineHeight
        var leftFillers: [Int: CGFloat] = [:], rightFillers: [Int: CGFloat] = [:]
        var leftTop: CGFloat = 0, rightTop: CGFloat = 0
        var leftColors: [Int: NSColor] = [:], rightColors: [Int: NSColor] = [:]
        for hunk in diff.hunks {
            let missing = CGFloat(hunk.right.count - hunk.left.count) * height
            // The room goes below the last line of the side's block, or above the first line.
            if missing > 0 {
                if hunk.left.upperBound == 0 { leftTop += missing } else { leftFillers[hunk.left.upperBound, default: 0] += missing }
            } else if missing < 0 {
                if hunk.right.upperBound == 0 { rightTop -= missing } else { rightFillers[hunk.right.upperBound, default: 0] -= missing }
            }
            let (leftColor, rightColor) = Self.colors(for: hunk.kind)
            for line in hunk.left { leftColors[line + 1] = leftColor }
            for line in hunk.right { rightColors[line + 1] = rightColor }
        }
        leftPane.lineFillers = leftFillers
        rightPane.lineFillers = rightFillers
        leftPane.textView.extraTopSpace = leftTop
        rightPane.textView.extraTopSpace = rightTop
        leftPane.diffMarks = EditorPane.DiffMarks(lineColors: leftColors, fillerColor: Self.fillerColor,
                                                  characters: diff.leftCharacters, characterColor: Self.characterColor)
        rightPane.diffMarks = EditorPane.DiffMarks(lineColors: rightColors, fillerColor: Self.fillerColor,
                                                   characters: diff.rightCharacters, characterColor: Self.characterColor)
        if let current = currentHunk, current >= diff.hunks.count { currentHunk = nil }
        updateStatus()
        strip.needsDisplay = true
        overview.needsDisplay = true
    }

    static func colors(for kind: TextDiff.Hunk.Kind) -> (NSColor, NSColor) {
        switch kind {
        case .changed: (changedColor, changedColor)
        case .deleted: (deletedColor, deletedColor)
        case .inserted: (insertedColor, insertedColor)
        }
    }

    static let changedColor = NSColor.systemBlue.withAlphaComponent(0.13)
    static let deletedColor = NSColor.systemRed.withAlphaComponent(0.14)
    static let insertedColor = NSColor.systemGreen.withAlphaComponent(0.15)
    static let characterColor = NSColor.systemBlue.withAlphaComponent(0.32)
    static let fillerColor = NSColor.secondaryLabelColor.withAlphaComponent(0.07)

    private func updateStatus() {
        guard let diff else { return }
        let count = diff.hunks.count
        if count == 0 {
            statusLabel.stringValue = String(localized: "Keine Unterschiede")
        } else if let current = currentHunk {
            statusLabel.stringValue = String(localized: "Unterschied \(current + 1) von \(count)")
        } else {
            statusLabel.stringValue = count == 1 ? String(localized: "1 Unterschied") : String(localized: "\(count) Unterschiede")
        }
    }

    // MARK: - Geometry

    var hunks: [TextDiff.Hunk] { diff?.hunks ?? [] }
    var leftLineCount: Int { left.document.lineIndex.lineCount }

    /// The top and bottom of a block in the left text view, room included; the same height on
    /// both sides, as they are aligned.
    func verticalRange(of hunk: TextDiff.Hunk) -> ClosedRange<CGFloat> {
        let view: EditorTextView = leftPane.textView
        let origin = view.textContainerOrigin
        let height = lineHeight
        let top: CGFloat
        if hunk.left.isEmpty {
            // Below the line before the block, where its room begins.
            if hunk.left.lowerBound == 0 {
                top = origin.y - view.extraTopSpace
            } else {
                top = lineFrame(hunk.left.lowerBound, in: leftPane).maxY - CGFloat(hunk.right.count) * height
            }
        } else {
            top = lineFrame(hunk.left.lowerBound + 1, in: leftPane).minY
        }
        return top...(top + CGFloat(max(hunk.left.count, hunk.right.count)) * height)
    }

    /// The frame of a line (from 1) in the pane's text view, room below it included.
    private func lineFrame(_ line: Int, in pane: EditorPane) -> NSRect {
        guard let content = pane.layoutManager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: pane.document.lineIndex.start(ofLine: line)),
              let fragment = pane.layoutManager.textLayoutFragment(for: location)
        else { return .zero }
        return fragment.layoutFragmentFrame.offsetBy(dx: 0, dy: pane.textView.textContainerOrigin.y)
    }

    func convertFromLeftText(_ y: CGFloat, to view: NSView) -> CGFloat {
        view.convert(NSPoint(x: 0, y: y), from: leftPane.textView).y
    }

    // MARK: - Scrolling together

    private func scrolled(_ pane: EditorPane) {
        guard !isSyncingScroll else { return }
        isSyncingScroll = true
        let other = pane === leftPane ? rightPane : leftPane
        let origin = pane.scrollView.contentView.bounds.origin
        other.scrollView.contentView.scroll(to: origin)
        other.scrollView.reflectScrolledClipView(other.scrollView.contentView)
        isSyncingScroll = false
        strip.needsDisplay = true
        overview.needsDisplay = true
    }

    /// Scrolls a block to a third of the window height.
    func reveal(_ index: Int) {
        guard hunks.indices.contains(index) else { return }
        currentHunk = index
        updateStatus()
        let range = verticalRange(of: hunks[index])
        let clip = leftPane.scrollView.contentView
        let maxY = max(leftPane.textView.frame.height - clip.bounds.height, 0)
        let y = (range.lowerBound - clip.bounds.height / 3).clamped(to: 0...maxY)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        leftPane.scrollView.reflectScrolledClipView(clip)
        // The insertion point goes to the block, so typing starts there.
        let hunk = hunks[index]
        let line = min(hunk.left.lowerBound + 1, max(leftLineCount, 1))
        leftPane.textView.setSelectedRange(NSRange(location: left.document.lineIndex.start(ofLine: line), length: 0))
        strip.needsDisplay = true
    }

    @objc func nextDifference(_ sender: Any?) {
        guard !hunks.isEmpty else { return NSSound.beep() }
        // Without a current block the first one from the top of the window on.
        let top = leftPane.scrollView.contentView.bounds.minY - 1
        let index = currentHunk.map { $0 + 1 } ?? hunks.firstIndex { verticalRange(of: $0).lowerBound > top } ?? 0
        reveal(index < hunks.count ? index : 0)
    }

    @objc func previousDifference(_ sender: Any?) {
        guard !hunks.isEmpty else { return NSSound.beep() }
        let index = currentHunk.map { $0 - 1 } ?? hunks.count - 1
        reveal(index >= 0 ? index : hunks.count - 1)
    }

    // MARK: - Taking a block over

    /// Replaces the block on one side by the lines of the other side, as one undo step there.
    func takeOver(_ index: Int, toLeft: Bool) {
        guard hunks.indices.contains(index) else { return }
        let hunk = hunks[index]
        let (source, target) = toLeft ? (right, left) : (left, right)
        let sourceLines = toLeft ? hunk.right : hunk.left
        let targetLines = toLeft ? hunk.left : hunk.right
        let targetPane = toLeft ? leftPane : rightPane
        guard !target.isReadOnly else { return NSSound.beep() }
        let text = Self.text(of: sourceLines, in: source.document)
        let range = Self.characterRange(of: targetLines, in: target.document)
        var replacement = text
        // At the end of a text without a final line break the lines need one between them.
        let targetString = target.document.textStorage.string as NSString
        if range.location == targetString.length, range.location > 0, targetString.character(at: range.location - 1) != 0x0A, !replacement.isEmpty {
            replacement = "\n" + replacement
            if replacement.hasSuffix("\n") { replacement.removeLast() }
        }
        let view: EditorTextView = targetPane.textView
        if view.shouldChangeText(in: range, replacementString: replacement) {
            view.textStorage?.replaceCharacters(in: range, with: replacement)
            view.didChangeText()
            view.undoManager?.setActionName(String(localized: "Block übernehmen"))
        }
        currentHunk = nil
        compare()
    }

    private static func text(of lines: Range<Int>, in document: TextDocument) -> String {
        guard !lines.isEmpty else { return "" }
        return (document.textStorage.string as NSString).substring(with: characterRange(of: lines, in: document))
    }

    /// The characters of lines (from 0), line breaks included; for an empty range the place
    /// where such lines would start.
    private static func characterRange(of lines: Range<Int>, in document: TextDocument) -> NSRange {
        let index = document.lineIndex
        let length = document.textStorage.length
        func start(_ line: Int) -> Int { line + 1 <= index.lineCount ? index.start(ofLine: line + 1) : length }
        let from = min(start(lines.lowerBound), length)
        let to = min(start(lines.upperBound), length)
        return NSRange(location: from, length: max(to - from, 0))
    }

    // MARK: - Unified diff

    private var unifiedDiff: String? {
        guard let diff else { return nil }
        return TextDiff.unified(left: left.document.textStorage.string, right: right.document.textStorage.string,
                                leftName: left.title, rightName: right.title, hunks: diff.hunks)
    }

    @objc func copyUnifiedDiff(_ sender: Any?) {
        guard let text = unifiedDiff else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func openUnifiedDiff(_ sender: Any?) {
        guard let text = unifiedDiff,
              let document = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? TextDocument
        else { return }
        document.restore(text: text, encoding: .utf8, hasBOM: false, lineEnding: .lf)
        if let diffLanguage = LanguageRegistry.shared.language(id: "diff") { document.setLanguage(diffLanguage, byUser: true) }
    }

    // MARK: - Saving and closing

    private var activeSide: CompareSide {
        view.window?.firstResponder === rightPane.textView ? right : left
    }

    /// ⌘S saves the side with the insertion point.
    @objc func save(_ sender: Any?) {
        let side = activeSide
        guard !side.isReadOnly else { return NSSound.beep() }
        side.document.save(sender)
    }

    /// Sides that are files opened only for the comparison ask before their changes are lost.
    func confirmClosing() -> Bool {
        for side in [left, right] where !side.isReadOnly && side.document.isDocumentEdited
            && !NSDocumentController.shared.documents.contains(where: { $0 === side.document }) {
            let alert = NSAlert()
            alert.messageText = String(localized: "Änderungen an „\(side.title)“ sichern?")
            alert.informativeText = String(localized: "Die Datei ist nur in diesem Vergleich geöffnet.")
            alert.addButton(withTitle: String(localized: "Sichern"))
            alert.addButton(withTitle: String(localized: "Abbrechen"))
            alert.addButton(withTitle: String(localized: "Nicht sichern"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: side.document.save(nil)
            case .alertSecondButtonReturn: return false
            default: break
            }
        }
        return true
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(save(_:)): return !activeSide.isReadOnly
        case #selector(nextDifference(_:)), #selector(previousDifference(_:)), #selector(copyUnifiedDiff(_:)), #selector(openUnifiedDiff(_:)):
            return !hunks.isEmpty
        default: return true
        }
    }
}

/// The strip between the two sides: a band for every block, joining both sides, with arrows
/// that take the block over to the other side.
final class CompareStrip: NSView {
    weak var compare: CompareViewController?

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Since macOS 14 views draw beyond their bounds unless told otherwise.
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private func bands() -> [(index: Int, rect: NSRect)] {
        guard let compare else { return [] }
        return compare.hunks.indices.compactMap { index in
            let range = compare.verticalRange(of: compare.hunks[index])
            let top = compare.convertFromLeftText(range.lowerBound, to: self)
            let bottom = compare.convertFromLeftText(range.upperBound, to: self)
            let rect = NSRect(x: 0, y: top, width: bounds.width, height: max(bottom - top, 2))
            return rect.intersects(bounds) ? (index, rect) : nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.intersection(bounds).fill()
        guard let compare else { return }
        for (index, rect) in bands() {
            let (color, _) = CompareViewController.colors(for: compare.hunks[index].kind)
            color.withAlphaComponent(0.3).setFill()
            rect.fill()
            guard rect.height >= 12 else { continue }
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.secondaryLabelColor]
            // An arrow only towards a side that can take the block.
            let midY = rect.midY - 7
            if !compare.left.isReadOnly { ("◀" as NSString).draw(at: NSPoint(x: 3, y: midY), withAttributes: attributes) }
            if !compare.right.isReadOnly { ("▶" as NSString).draw(at: NSPoint(x: bounds.width - 13, y: midY), withAttributes: attributes) }
        }
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
        NSRect(x: bounds.width - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
    }

    /// A click on the left half takes the block from the right side over to the left, and the other way round.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let (index, _) = bands().first(where: { $0.rect.contains(point) }) else { return }
        compare?.takeOver(index, toLeft: point.x < bounds.width / 2)
    }

    override func resetCursorRects() {
        guard let compare else { return }
        for (_, rect) in bands() {
            var left = rect, right = rect
            left.size.width = rect.width / 2
            right.origin.x = left.maxX
            right.size.width = rect.width - left.width
            if !compare.left.isReadOnly { addCursorRect(left, cursor: .pointingHand) }
            if !compare.right.isReadOnly { addCursorRect(right, cursor: .pointingHand) }
        }
    }
}

/// The bar at the right edge: every difference of the whole text as a mark; a click jumps to it.
final class CompareOverview: NSView {
    weak var compare: CompareViewController?

    override init(frame: NSRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private func marks() -> [(index: Int, rect: NSRect)] {
        guard let compare else { return [] }
        let total = CGFloat(max(compare.leftLineCount, 1))
        return compare.hunks.enumerated().map { index, hunk in
            let y = CGFloat(hunk.left.lowerBound) / total * (bounds.height - 4) + 2
            let height = max(CGFloat(max(hunk.left.count, 1)) / total * bounds.height, 3)
            return (index, NSRect(x: 2, y: y, width: bounds.width - 4, height: height))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.intersection(bounds).fill()
        guard let compare else { return }
        for (index, rect) in marks() {
            let (color, _) = CompareViewController.colors(for: compare.hunks[index].kind)
            color.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let nearest = marks().min { abs($0.rect.midY - point.y) < abs($1.rect.midY - point.y) }
        if let nearest { compare?.reveal(nearest.index) }
    }
}
