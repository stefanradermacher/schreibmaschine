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

/// The bar above the text for searching, replacing and going to a line, like in PhpStorm:
/// part of the window, not a panel of its own.
final class FindBar: NSView, NSTextFieldDelegate {
    enum Mode { case find, replace, goToLine }

    weak var delegate: FindBarDelegate?
    private(set) var mode: Mode = .find

    let searchField = GrowingTextField()
    let replaceField = GrowingTextField()
    private let historyButton = FindBar.iconButton("clock.arrow.circlepath", String(localized: "Letzte Suchbegriffe"))
    private let caseButton = FindBar.toggle("Aa", String(localized: "Groß- und Kleinschreibung beachten"))
    private let wordButton = FindBar.toggle("W", String(localized: "Nur ganze Wörter"))
    private let regexButton = FindBar.toggle(".*", String(localized: "Regulärer Ausdruck"))
    private let selectionButton = FindBar.toggle(nil, String(localized: "Nur in der Auswahl suchen"), symbol: "text.line.first.and.arrowtriangle.forward")
    private let statusLabel = NSTextField(labelWithString: "")
    private let previousButton = FindBar.iconButton("chevron.up", String(localized: "Vorheriger Treffer (⇧↩)"))
    private let nextButton = FindBar.iconButton("chevron.down", String(localized: "Nächster Treffer (↩)"))
    private let closeButton = FindBar.iconButton("xmark", String(localized: "Schließen (Esc)"))
    private let replaceButton = NSButton(title: String(localized: "Ersetzen"), target: nil, action: nil)
    private let replaceAllButton = NSButton(title: String(localized: "Alle ersetzen"), target: nil, action: nil)
    private let previewLabel = NSTextField(labelWithString: "")
    private var replaceRow: NSStackView!
    private var previewRow: NSStackView!
    private var findControls: [NSView] = []

    private static let defaults = UserDefaults.standard

    init() {
        super.init(frame: .zero)

        for field in [searchField, replaceField] {
            field.delegate = self
            field.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        replaceField.placeholderString = String(localized: "Ersetzen durch")

        caseButton.state = Self.defaults.bool(forKey: Preferences.searchCaseSensitive) ? .on : .off
        wordButton.state = Self.defaults.bool(forKey: Preferences.searchWholeWords) ? .on : .off
        regexButton.state = Self.defaults.bool(forKey: Preferences.searchRegularExpression) ? .on : .off
        for button in [caseButton, wordButton, regexButton] {
            button.target = self
            button.action = #selector(optionChanged(_:))
        }
        selectionButton.target = self
        selectionButton.action = #selector(scopeChanged(_:))

        historyButton.target = self
        historyButton.action = #selector(showHistory(_:))
        previousButton.target = self
        previousButton.action = #selector(previous(_:))
        nextButton.target = self
        nextButton.action = #selector(next(_:))
        closeButton.target = self
        closeButton.action = #selector(close(_:))
        replaceButton.target = self
        replaceButton.action = #selector(replace(_:))
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAll(_:))
        for button in [replaceButton, replaceAllButton] {
            button.controlSize = .small
            button.bezelStyle = .push
            button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        }
        replaceButton.toolTip = String(localized: "Aktuellen Treffer ersetzen und zum nächsten gehen (↩ im Ersetzen-Feld)")

        statusLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        previewLabel.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.lineBreakMode = .byTruncatingMiddle
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let options = NSStackView(views: [caseButton, wordButton, regexButton, selectionButton])
        options.spacing = 2
        findControls = [options, previousButton, nextButton]

        let findRow = NSStackView(views: [historyButton, searchField, options, statusLabel, previousButton, nextButton, closeButton])
        findRow.alignment = .top
        findRow.spacing = 6
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 22).isActive = true
        replaceRow = NSStackView(views: [spacer, replaceField, replaceButton, replaceAllButton])
        replaceRow.alignment = .top
        replaceRow.spacing = 6
        let previewSpacer = NSView()
        previewSpacer.widthAnchor.constraint(equalToConstant: 22).isActive = true
        previewRow = NSStackView(views: [previewSpacer, previewLabel])
        previewRow.spacing = 6

        let rows = NSStackView(views: [findRow, replaceRow, previewRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        rows.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        for row in [findRow, replaceRow!, previewRow!] {
            row.widthAnchor.constraint(equalTo: rows.widthAnchor, constant: -16).isActive = true
        }

        let separator = NSBox()
        separator.boxType = .separator
        for view in [rows, separator] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: rows.bottomAnchor),
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
                    caseSensitive: caseButton.state == .on,
                    wholeWords: wordButton.state == .on,
                    regularExpression: regexButton.state == .on)
    }

    var replacementTemplate: String { replaceField.stringValue }
    var isRegularExpression: Bool { regexButton.state == .on }

    var searchesInSelection: Bool {
        get { selectionButton.state == .on }
        set { selectionButton.state = newValue ? .on : .off }
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
        let goTo = mode == .goToLine
        findControls.forEach { $0.isHidden = goTo }
        historyButton.isHidden = goTo
        replaceRow.isHidden = mode != .replace
        previewRow.isHidden = mode != .replace || previewLabel.stringValue.isEmpty
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

    /// Shows a short status next to the field; a longer explanation goes into the tooltip.
    func setStatus(_ text: String, isError: Bool = false, detail: String? = nil) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        statusLabel.toolTip = detail ?? text
        searchField.toolTip = detail
    }

    /// Marks the search field as invalid, for a regular expression that does not compile or a
    /// line that does not exist.
    func setError(_ isError: Bool) {
        searchField.textColor = isError ? .systemRed : .textColor
    }

    func setPreview(_ text: String?) {
        previewLabel.stringValue = text.map { String(localized: "Wird zu: \($0)") } ?? ""
        previewRow.isHidden = mode != .replace || text == nil
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

    @objc private func showHistory(_ sender: Any?) {
        let menu = NSMenu()
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
        menu.popUp(positioning: nil, at: NSPoint(x: searchField.frame.minX, y: searchField.frame.maxY + 4), in: searchField.superview)
    }

    @objc private func historyChosen(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        setSearchText(text)
        delegate?.findBarQueryDidChange(self)
        focusSearchField()
    }

    // MARK: - Actions

    @objc private func optionChanged(_ sender: NSButton) {
        Self.defaults.set(caseButton.state == .on, forKey: Preferences.searchCaseSensitive)
        Self.defaults.set(wordButton.state == .on, forKey: Preferences.searchWholeWords)
        Self.defaults.set(regexButton.state == .on, forKey: Preferences.searchRegularExpression)
        delegate?.findBarQueryDidChange(self)
    }

    @objc private func scopeChanged(_ sender: NSButton) { delegate?.findBarScopeDidChange(self) }
    @objc private func previous(_ sender: Any?) { delegate?.findBar(self, findNextBackwards: true) }
    @objc private func next(_ sender: Any?) { delegate?.findBar(self, findNextBackwards: false) }
    @objc private func close(_ sender: Any?) { delegate?.findBarClose(self) }
    @objc private func replace(_ sender: Any?) { delegate?.findBarReplace(self) }
    @objc private func replaceAll(_ sender: Any?) { delegate?.findBarReplaceAll(self) }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? GrowingTextField else { return }
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
            showHistory(nil)
            return true
        default:
            // ⌥↩ inserts a line break: search terms may span lines.
            return false
        }
    }

    // MARK: - Buttons

    private static func toggle(_ title: String?, _ toolTip: String, symbol: String? = nil) -> NSButton {
        let button = NSButton(title: title ?? "", target: nil, action: nil)
        if let symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip) }
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
        return button
    }

    private static func iconButton(_ symbol: String, _ toolTip: String) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)!, target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.toolTip = toolTip
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }
}

/// A text field that grows with its text up to a few lines; ⌥↩ inserts a line break.
final class GrowingTextField: NSTextField {
    var maxLines: CGFloat = 4

    convenience init() {
        self.init(frame: .zero)
        usesSingleLineMode = false
        cell?.wraps = true
        cell?.isScrollable = false
        lineBreakMode = .byCharWrapping
        bezelStyle = .roundedBezel
    }

    override var intrinsicContentSize: NSSize {
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let text = currentEditor()?.string ?? stringValue
        let width = max(bounds.width - 8, 40)
        var height = ((text.isEmpty ? " " : text) as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: [.font: font]).height
        if text.hasSuffix("\n") { height += font.boundingRectForFont.height }
        let line = ceil(font.ascender - font.descender + font.leading)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(min(max(height, line), line * maxLines)) + 6)
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
