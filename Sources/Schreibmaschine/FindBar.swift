import AppKit

protocol FindBarDelegate: AnyObject {
    func findBarQueryDidChange(_ bar: FindBar)
    func findBar(_ bar: FindBar, findNextBackwards backwards: Bool)
    func findBarReplace(_ bar: FindBar)
    func findBarReplaceAll(_ bar: FindBar)
    func findBarReplacementDidChange(_ bar: FindBar)
    func findBarScopeDidChange(_ bar: FindBar)
    func findBar(_ bar: FindBar, goTo input: String)
    func findBarClose(_ bar: FindBar)
}

/// The bar above the text for searching, replacing and going to a line: part of the window,
/// not a panel of its own. Its controls follow Apple's find bars (Safari, TextEdit, Xcode):
/// the search field carries the recent searches (magnifier with arrow) on the left and the
/// match count on the right, previous and next are a segmented control, "Done" closes.
final class FindBar: NSView, NSTextFieldDelegate, NSMenuDelegate {
    enum Mode { case find, replace, goToLine }

    weak var delegate: FindBarDelegate?
    private(set) var mode: Mode = .find

    let searchField = FindField(withHistory: true)
    let replaceField = FindField(withHistory: false)

    private enum Option: Int { case matchCase, wholeWords, regularExpression, selection }
    private let options = NSSegmentedControl()
    private let navigation = NSSegmentedControl()
    private let doneButton = NSButton(title: String(localized: "Fertig"), target: nil, action: nil)
    private let replaceButton = NSButton(title: String(localized: "Ersetzen"), target: nil, action: nil)
    private let replaceAllButton = NSButton(title: String(localized: "Alle ersetzen"), target: nil, action: nil)
    private let previewLabel = NSTextField(labelWithString: "")
    private let grid: NSGridView

    private static let defaults = UserDefaults.standard

    init() {
        // Options: a segmented control that allows any combination, as in Xcode.
        options.segmentCount = 4
        options.trackingMode = .selectAny
        options.setLabel("Aa", forSegment: Option.matchCase.rawValue)
        options.setLabel("W", forSegment: Option.wholeWords.rawValue)
        options.setLabel(".*", forSegment: Option.regularExpression.rawValue)
        let scopeLabel = String(localized: "Nur in der Auswahl suchen")
        options.setImage(NSImage(systemSymbolName: "text.line.first.and.arrowtriangle.forward", accessibilityDescription: scopeLabel),
                         forSegment: Option.selection.rawValue)
        options.setToolTip(String(localized: "Groß- und Kleinschreibung beachten"), forSegment: Option.matchCase.rawValue)
        options.setToolTip(String(localized: "Nur ganze Wörter"), forSegment: Option.wholeWords.rawValue)
        options.setToolTip(String(localized: "Regulärer Ausdruck"), forSegment: Option.regularExpression.rawValue)
        options.setToolTip(scopeLabel, forSegment: Option.selection.rawValue)
        options.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium)
        for segment in 0..<3 { options.setWidth(30, forSegment: segment) }
        options.setSelected(Self.defaults.bool(forKey: Preferences.searchCaseSensitive), forSegment: Option.matchCase.rawValue)
        options.setSelected(Self.defaults.bool(forKey: Preferences.searchWholeWords), forSegment: Option.wholeWords.rawValue)
        options.setSelected(Self.defaults.bool(forKey: Preferences.searchRegularExpression), forSegment: Option.regularExpression.rawValue)

        // Previous and next, as in Safari and Xcode.
        navigation.segmentCount = 2
        navigation.trackingMode = .momentary
        navigation.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: String(localized: "Vorheriger Treffer")), forSegment: 0)
        navigation.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: String(localized: "Nächster Treffer")), forSegment: 1)
        navigation.setToolTip(String(localized: "Vorheriger Treffer (⇧↩)"), forSegment: 0)
        navigation.setToolTip(String(localized: "Nächster Treffer (↩)"), forSegment: 1)
        navigation.setWidth(28, forSegment: 0)
        navigation.setWidth(28, forSegment: 1)

        doneButton.bezelStyle = .push
        doneButton.toolTip = String(localized: "Suchleiste schließen (Esc)")
        replaceButton.bezelStyle = .push
        replaceButton.toolTip = String(localized: "Aktuellen Treffer ersetzen und zum nächsten gehen (↩ im Ersetzen-Feld)")
        replaceAllButton.bezelStyle = .push

        previewLabel.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.lineBreakMode = .byTruncatingMiddle
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        replaceField.placeholderString = String(localized: "Ersetzen durch")

        let findControls = NSStackView(views: [options, navigation, doneButton])
        findControls.spacing = 8
        let replaceControls = NSStackView(views: [replaceButton, replaceAllButton])
        replaceControls.spacing = 8
        // The controls keep their size; the fields take the rest of the width.
        for stack in [findControls, replaceControls] {
            stack.setHuggingPriority(.required, for: .horizontal)
            stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        // A grid keeps the two fields exactly above each other and the buttons in one column.
        grid = NSGridView(views: [
            [searchField, findControls],
            [replaceField, replaceControls],
            [previewLabel, NSGridCell.emptyContentView],
        ])
        grid.columnSpacing = 8
        grid.rowSpacing = 6
        grid.yPlacement = .center
        grid.column(at: 1).xPlacement = .leading
        grid.column(at: 0).xPlacement = .fill

        super.init(frame: .zero)

        for field in [searchField, replaceField] {
            field.delegate = self
            field.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        }
        searchField.historyMenu.delegate = self
        options.target = self
        options.action = #selector(optionChanged(_:))
        navigation.target = self
        navigation.action = #selector(navigate(_:))
        doneButton.target = self
        doneButton.action = #selector(close(_:))
        replaceButton.target = self
        replaceButton.action = #selector(replace(_:))
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAll(_:))

        let separator = NSBox()
        separator.boxType = .separator
        for view in [grid, separator] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            separator.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 7),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        searchField.nextKeyView = replaceField
        replaceField.nextKeyView = searchField
        setMode(.find)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }

    // MARK: - State

    var query: SearchQuery {
        SearchQuery(text: searchField.stringValue,
                    caseSensitive: options.isSelected(forSegment: Option.matchCase.rawValue),
                    wholeWords: options.isSelected(forSegment: Option.wholeWords.rawValue),
                    regularExpression: options.isSelected(forSegment: Option.regularExpression.rawValue))
    }

    var replacementTemplate: String { replaceField.stringValue }
    var isRegularExpression: Bool { options.isSelected(forSegment: Option.regularExpression.rawValue) }

    var searchesInSelection: Bool {
        get { options.isSelected(forSegment: Option.selection.rawValue) }
        set { options.setSelected(newValue, forSegment: Option.selection.rawValue) }
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
        let goTo = mode == .goToLine
        options.isHidden = goTo
        navigation.isHidden = goTo
        searchField.showsHistory = !goTo
        grid.row(at: 1).isHidden = mode != .replace
        grid.row(at: 2).isHidden = mode != .replace || previewLabel.stringValue.isEmpty
        searchField.placeholderString = goTo
            ? String(localized: "Zeile, Zeile:Spalte, +Zeilen oder -Zeilen")
            : String(localized: "Suchen")
        if goTo {
            searchField.stringValue = ""
        }
        setStatus("")
        setError(false)
    }

    func setSearchText(_ text: String) {
        searchField.stringValue = text
        searchField.invalidateIntrinsicContentSize()
    }

    /// Shows a short status inside the search field, on the right; a longer explanation goes
    /// into the tooltip. The space for it is fixed, so nothing moves when it changes.
    func setStatus(_ text: String, isError: Bool = false, detail: String? = nil) {
        searchField.status.stringValue = text
        searchField.status.textColor = isError ? .systemRed : .secondaryLabelColor
        searchField.status.toolTip = detail ?? text
        searchField.toolTip = detail
    }

    /// Marks the search text as invalid, for a regular expression that does not compile or a
    /// line that does not exist.
    func setError(_ isError: Bool) {
        searchField.textColor = isError ? .systemRed : .textColor
    }

    func setPreview(_ text: String?) {
        previewLabel.stringValue = text.map { String(localized: "Wird zu: \($0)") } ?? ""
        grid.row(at: 2).isHidden = mode != .replace || text == nil
    }

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    // MARK: - History

    static func remember(_ text: String) {
        guard !text.isEmpty else { return }
        var history = defaults.stringArray(forKey: Preferences.searchHistory) ?? []
        history.removeAll { $0 == text }
        history.insert(text, at: 0)
        defaults.set(Array(history.prefix(20)), forKey: Preferences.searchHistory)
    }

    /// Fills the menu of the magnifier with the recent searches when it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        // The first item is the pull-down's face, the magnifier; the others are rebuilt.
        while menu.items.count > 1 { menu.removeItem(at: 1) }
        let header = NSMenuItem(title: String(localized: "Letzte Suchbegriffe"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let history = Self.defaults.stringArray(forKey: Preferences.searchHistory) ?? []
        if history.isEmpty {
            let empty = NSMenuItem(title: String(localized: "Noch keine Suchbegriffe"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for text in history {
            let title = text.replacingOccurrences(of: "\n", with: " ⏎ ")
            let item = NSMenuItem(title: String(title.prefix(80)), action: #selector(historyChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = text
            menu.addItem(item)
        }
        if !history.isEmpty {
            menu.addItem(.separator())
            let clear = NSMenuItem(title: String(localized: "Verlauf löschen"), action: #selector(clearHistory(_:)), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }
    }

    @objc private func historyChosen(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        setSearchText(text)
        delegate?.findBarQueryDidChange(self)
        focusSearchField()
    }

    @objc private func clearHistory(_ sender: Any?) {
        Self.defaults.removeObject(forKey: Preferences.searchHistory)
    }

    // MARK: - Actions

    @objc private func optionChanged(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == Option.selection.rawValue {
            delegate?.findBarScopeDidChange(self)
            return
        }
        Self.defaults.set(options.isSelected(forSegment: Option.matchCase.rawValue), forKey: Preferences.searchCaseSensitive)
        Self.defaults.set(options.isSelected(forSegment: Option.wholeWords.rawValue), forKey: Preferences.searchWholeWords)
        Self.defaults.set(options.isSelected(forSegment: Option.regularExpression.rawValue), forKey: Preferences.searchRegularExpression)
        delegate?.findBarQueryDidChange(self)
    }

    @objc private func navigate(_ sender: NSSegmentedControl) {
        delegate?.findBar(self, findNextBackwards: sender.selectedSegment == 0)
    }

    @objc private func close(_ sender: Any?) { delegate?.findBarClose(self) }
    @objc private func replace(_ sender: Any?) { delegate?.findBarReplace(self) }
    @objc private func replaceAll(_ sender: Any?) { delegate?.findBarReplaceAll(self) }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? FindField else { return }
        field.invalidateIntrinsicContentSize()
        if field === searchField, mode == .goToLine {
            // A pasted "120⏎" goes to the line like typing 120 and ↩.
            let text = field.stringValue
            if text.contains("\n") {
                field.stringValue = text.replacingOccurrences(of: "\n", with: "")
                delegate?.findBar(self, goTo: field.stringValue)
            } else {
                setError(false)
            }
        } else if field === searchField {
            delegate?.findBarQueryDidChange(self)
        } else if field === replaceField {
            delegate?.findBarReplacementDidChange(self)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            if mode == .goToLine {
                delegate?.findBar(self, goTo: searchField.stringValue)
            } else if control === replaceField {
                delegate?.findBarReplace(self)
            } else {
                delegate?.findBar(self, findNextBackwards: backwards)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            delegate?.findBarClose(self)
            return true
        case #selector(NSResponder.moveDown(_:)) where control === searchField && !textView.string.contains("\n") && mode != .goToLine:
            searchField.showHistory()
            return true
        default:
            // ⌥↩ inserts a line break: search terms may span lines.
            return false
        }
    }
}

/// The text field of the find bar: rounded like a search field, grows with its text up to a
/// few lines (⌥↩ inserts a line break), with the recent searches as a pull-down magnifier on
/// the left and a status such as "3 von 17" on the right, both inside the field.
final class FindField: NSTextField {
    let status = NSTextField(labelWithString: "")
    let historyMenu = NSMenu()
    private let historyButton = NSPopUpButton(frame: .zero, pullsDown: true)
    var maxLines: CGFloat = 4

    /// Width kept free for the status on the right, so the text never runs under it.
    private static let statusWidth: CGFloat = 104
    private static let historyWidth: CGFloat = 30

    var showsHistory = true {
        didSet { updateHistoryVisibility() }
    }

    private func updateHistoryVisibility() {
        historyButton.isHidden = !showsHistory
        insetCell.leftInset = showsHistory ? Self.historyWidth : 6
        needsDisplay = true
    }

    override class var cellClass: AnyClass? {
        get { InsetTextFieldCell.self }
        set {}
    }

    private var insetCell: InsetTextFieldCell { cell as! InsetTextFieldCell }

    init(withHistory: Bool) {
        super.init(frame: .zero)
        isEditable = true
        isSelectable = true
        isBezeled = true
        bezelStyle = .roundedBezel
        usesSingleLineMode = false
        cell?.wraps = true
        cell?.isScrollable = false
        lineBreakMode = .byCharWrapping
        font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)

        status.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        status.textColor = .secondaryLabelColor
        status.alignment = .right
        status.lineBreakMode = .byTruncatingTail
        historyButton.isBordered = false
        historyButton.menu = historyMenu
        historyButton.toolTip = String(localized: "Letzte Suchbegriffe")
        (historyButton.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        historyButton.imagePosition = .imageOnly
        let magnifier = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: String(localized: "Letzte Suchbegriffe"))
        historyMenu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
        historyMenu.item(at: 0)?.image = magnifier
        (historyButton.cell as? NSPopUpButtonCell)?.usesItemFromMenu = true

        for view in [status, historyButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // Both sit on the first line, also when the field has grown.
        let firstLineCenter = (lineHeight + 6) / 2
        NSLayoutConstraint.activate([
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            status.widthAnchor.constraint(equalToConstant: Self.statusWidth - 12),
            status.centerYAnchor.constraint(equalTo: topAnchor, constant: firstLineCenter),
            historyButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            historyButton.widthAnchor.constraint(equalToConstant: Self.historyWidth - 4),
            historyButton.centerYAnchor.constraint(equalTo: topAnchor, constant: firstLineCenter),
        ])
        insetCell.rightInset = withHistory ? Self.statusWidth : 6
        showsHistory = withHistory
        // Property observers do not run in the initializer.
        updateHistoryVisibility()
        status.isHidden = !withHistory
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showHistory() {
        historyButton.performClick(nil)
    }

    private var lineHeight: CGFloat {
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return ceil(font.ascender - font.descender + font.leading)
    }

    override var intrinsicContentSize: NSSize {
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let text = currentEditor()?.string ?? stringValue
        let width = max(bounds.width - insetCell.leftInset - insetCell.rightInset - 4, 40)
        var height = ((text.isEmpty ? " " : text) as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: [.font: font]).height
        if text.hasSuffix("\n") { height += lineHeight }
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(min(max(height, lineHeight), lineHeight * maxLines)) + 6)
    }

    private var laidOutWidth: CGFloat = 0

    // The height depends on the width; only a new width needs a new height.
    override func layout() {
        super.layout()
        if bounds.width != laidOutWidth {
            laidOutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}

/// Keeps the text clear of the controls inside the field on the left and right.
final class InsetTextFieldCell: NSTextFieldCell {
    var leftInset: CGFloat = 6
    var rightInset: CGFloat = 6

    private func inset(_ rect: NSRect) -> NSRect {
        var rect = rect
        rect.origin.x += leftInset - 2
        rect.size.width -= leftInset + rightInset - 4
        return rect
    }

    // The field editor is placed by the drawing rect as well, so this one override covers
    // both showing and editing the text.
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        inset(super.drawingRect(forBounds: rect))
    }
}
