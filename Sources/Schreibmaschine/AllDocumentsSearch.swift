import AppKit

/// Search in all open documents (⇧⌘F). There is one list of results for the whole app; every
/// editor shows it in a sidebar on the left while the search is active, so the list stays in
/// view when a click on a result switches to another tab.
final class AllDocumentsSearch {
    static let shared = AllDocumentsSearch()
    static let didChange = Notification.Name("AllDocumentsSearchDidChange")

    final class Group {
        weak var document: TextDocument?
        let name: String
        var items: [Item]
        init(document: TextDocument, items: [Item]) {
            self.document = document
            self.name = document.displayName
            self.items = items
        }
    }

    final class Item {
        let range: NSRange
        let line: Int
        let preview: NSAttributedString
        weak var group: Group?
        init(range: NSRange, line: Int, preview: NSAttributedString) {
            self.range = range
            self.line = line
            self.preview = preview
        }
    }

    private(set) var isActive = false
    private(set) var text = ""
    private(set) var groups: [Group] = []
    private(set) var failure: String?
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers = [
            // Edits in any document, and options changed in a find bar, search again.
            center.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self, isActive, let storage = notification.object as? NSTextStorage,
                      storage.editedMask.contains(.editedCharacters),
                      NSDocumentController.shared.documents.contains(where: { ($0 as? TextDocument)?.textStorage === storage })
                else { return }
                scheduleSearch()
            },
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, isActive, query != lastQuery else { return }
                scheduleSearch()
            },
        ]
    }

    var query: SearchQuery {
        let defaults = UserDefaults.standard
        return SearchQuery(text: text,
                           caseSensitive: defaults.bool(forKey: Preferences.searchCaseSensitive),
                           wholeWords: defaults.bool(forKey: Preferences.searchWholeWords),
                           regularExpression: defaults.bool(forKey: Preferences.searchRegularExpression))
    }

    private var lastQuery: SearchQuery?

    var matchCount: Int { groups.reduce(0) { $0 + $1.items.count } }

    func activate(with text: String?) {
        if let text { self.text = text }
        isActive = true
        search()
    }

    func deactivate() {
        isActive = false
        groups = []
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func setText(_ text: String) {
        guard text != self.text else { return }
        self.text = text
        search()
    }

    private func scheduleSearch() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.search() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func search() {
        pending?.cancel()
        pending = nil
        let query = self.query
        lastQuery = query
        failure = nil
        groups = []
        if !query.isEmpty {
            do {
                for document in NSDocumentController.shared.documents.compactMap({ $0 as? TextDocument }) {
                    let string = document.textStorage.string
                    let matches = try query.matches(in: string, limit: 5_000)
                    guard !matches.isEmpty else { continue }
                    let items = matches.map { match in
                        Item(range: match.range, line: document.lineIndex.lineNumber(at: match.range.location),
                             preview: Self.preview(of: match.range, in: string as NSString))
                    }
                    let group = Group(document: document, items: items)
                    items.forEach { $0.group = group }
                    groups.append(group)
                }
            } catch SearchQuery.Failure.invalidPattern(let message) {
                failure = message
            } catch {}
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    /// The line of a match, without its indentation and shortened around the match, which is bold.
    private static func preview(of range: NSRange, in string: NSString) -> NSAttributedString {
        let lineRange = string.lineRange(for: NSRange(location: range.location, length: 0))
        var start = lineRange.location
        var end = lineRange.upperBound
        while start < range.location, [0x20, 0x09].contains(string.character(at: start)) { start += 1 }
        while end > max(start, range.upperBound), [0x0A, 0x0D].contains(string.character(at: end - 1)) { end -= 1 }
        // Long lines: some context before the match, the rest cut.
        if range.location - start > 40 { start = range.location - 30 }
        end = min(end, max(range.upperBound, start) + 120)
        let matchEnd = min(range.upperBound, end)
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .bold)
        let result = NSMutableAttributedString()
        if start > lineRange.location, string.substring(with: NSRange(location: lineRange.location, length: start - lineRange.location)).contains(where: { !$0.isWhitespace }) {
            result.append(NSAttributedString(string: "…", attributes: [.font: font]))
        }
        result.append(NSAttributedString(string: string.substring(with: NSRange(location: start, length: range.location - start)), attributes: [.font: font]))
        result.append(NSAttributedString(string: string.substring(with: NSRange(location: range.location, length: matchEnd - range.location)).replacingOccurrences(of: "\n", with: "⏎"),
                                         attributes: [.font: bold, .backgroundColor: NSColor.findHighlightColor.withAlphaComponent(0.45)]))
        if matchEnd < end {
            result.append(NSAttributedString(string: string.substring(with: NSRange(location: matchEnd, length: end - matchEnd)), attributes: [.font: font]))
        }
        return result
    }

    /// Replaces every match in every open document; each document can undo it on its own.
    func replaceAll(with template: String) -> Int {
        search()
        let query = self.query
        var count = 0
        for group in groups {
            guard let document = group.document, let textView = document.editor?.textView else { continue }
            let string = textView.string
            guard let matches = try? query.matches(in: string) else { continue }
            var ranges: [NSValue] = []
            var replacements: [String] = []
            for match in matches {
                guard let replacement = try? query.replacement(for: match, in: string, template: template) else { continue }
                ranges.append(NSValue(range: match.range))
                replacements.append(replacement)
            }
            guard !ranges.isEmpty, textView.shouldChangeText(inRanges: ranges, replacementStrings: replacements),
                  let storage = textView.textStorage else { continue }
            storage.beginEditing()
            for (range, replacement) in zip(ranges, replacements).reversed() {
                storage.replaceCharacters(in: range.rangeValue, with: replacement)
            }
            storage.endEditing()
            textView.didChangeText()
            textView.undoManager?.setActionName(String(localized: "Alle ersetzen"))
            count += replacements.count
        }
        search()
        return count
    }

    /// Shows a match: its document in front, the match selected.
    func reveal(_ item: Item) {
        guard let document = item.group?.document, let controller = document.windowControllers.first as? DocumentWindowController,
              let window = controller.window, let textView = controller.editor?.textView
        else { return }
        window.makeKeyAndOrderFront(nil)
        let length = (textView.string as NSString).length
        guard item.range.upperBound <= length else { return }
        textView.setSelectedRange(item.range)
        textView.scrollRangeToVisible(item.range)
        textView.showFindIndicator(for: item.range)
    }
}

/// The sidebar with the search in all open documents: search and replace field, and the matches
/// grouped by document.
final class AllDocumentsSearchView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    private let model = AllDocumentsSearch.shared
    let searchField = NSSearchField()
    private let replaceField = NSTextField()
    private let replaceAllButton = NSButton(title: String(localized: "Alle ersetzen"), target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let outline = NSOutlineView()
    private var observer: NSObjectProtocol?

    init() {
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: String(localized: "In allen offenen Dokumenten"))
        title.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Schließen"))!, target: self, action: #selector(closeSearch(_:)))
        close.isBordered = false
        close.toolTip = String(localized: "Schließen (Esc)")

        searchField.placeholderString = String(localized: "Suchen")
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = false
        searchField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
        replaceField.placeholderString = String(localized: "Ersetzen durch")
        replaceField.font = searchField.font
        replaceField.delegate = self
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAll(_:))
        replaceAllButton.controlSize = .small
        replaceAllButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        replaceAllButton.toolTip = String(localized: "In allen Dokumenten ersetzen; jedes Dokument kann es einzeln widerrufen")
        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("match"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .small
        outline.usesAutomaticRowHeights = true
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(rowClicked(_:))
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let header = NSStackView(views: [title, NSView(), close])
        let replaceRow = NSStackView(views: [replaceField, replaceAllButton])
        replaceRow.spacing = 6
        let stack = NSStackView(views: [header, searchField, replaceRow, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 4, right: 8)

        let separator = NSBox()
        separator.boxType = .separator
        for view in [stack, scroll, separator] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: separator.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: stack.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: separator.leadingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
        ])

        observer = NotificationCenter.default.addObserver(forName: AllDocumentsSearch.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }

    func focus() {
        window?.makeFirstResponder(searchField)
    }

    private func update() {
        if window?.firstResponder !== searchField.currentEditor(), searchField.stringValue != model.text {
            searchField.stringValue = model.text
        }
        if let failure = model.failure {
            statusLabel.stringValue = String(localized: "Ungültiger Ausdruck")
            statusLabel.textColor = .systemRed
            statusLabel.toolTip = failure
        } else if model.text.isEmpty {
            statusLabel.stringValue = ""
        } else {
            let count = model.matchCount
            let documents = model.groups.count
            statusLabel.textColor = count == 0 ? .systemRed : .secondaryLabelColor
            statusLabel.toolTip = nil
            statusLabel.stringValue = count == 0
                ? String(localized: "Keine Treffer")
                : String(localized: "\(count.formatted()) Treffer in \(documents.formatted()) Dokumenten")
        }
        outline.reloadData()
        // Few documents: all expanded; many: collapsed, so the list stays readable.
        if model.groups.count <= 5 { outline.expandItem(nil, expandChildren: true) }
    }

    // MARK: - Actions

    func controlTextDidChange(_ notification: Notification) {
        if notification.object as? NSSearchField === searchField {
            model.setText(searchField.stringValue)
            SearchController.findPasteboardText = searchField.stringValue
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            if control === searchField, !searchField.stringValue.isEmpty { return false }
            closeSearch(nil)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)), control === searchField {
            // ↩ goes to the first match.
            if let first = model.groups.first?.items.first { model.reveal(first) }
            FindBar.remember(searchField.stringValue)
            return true
        }
        return false
    }

    @objc private func closeSearch(_ sender: Any?) {
        FindBar.remember(model.text)
        model.deactivate()
    }

    @objc private func replaceAll(_ sender: Any?) {
        let count = model.replaceAll(with: replaceField.stringValue)
        statusLabel.stringValue = count == 1 ? String(localized: "1 Treffer ersetzt") : String(localized: "\(count.formatted()) Treffer ersetzt")
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard let item = outline.item(atRow: row) else { return }
        if let match = item as? AllDocumentsSearch.Item {
            model.reveal(match)
        } else if outline.isItemExpanded(item) {
            outline.collapseItem(item)
        } else {
            outline.expandItem(item)
        }
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return model.groups.count }
        return (item as? AllDocumentsSearch.Group)?.items.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return model.groups[index] }
        return (item as! AllDocumentsSearch.Group).items[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is AllDocumentsSearch.Group
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        // Not set as the cell's textField: the outline view would give it its own font and drop
        // the bold match.
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -2),
        ])
        if let group = item as? AllDocumentsSearch.Group {
            let text = NSMutableAttributedString(string: group.name, attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)])
            text.append(NSAttributedString(string: "  \(group.items.count.formatted())", attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]))
            label.attributedStringValue = text
            label.toolTip = group.document?.fileURL?.path
        } else if let match = item as? AllDocumentsSearch.Item {
            let text = NSMutableAttributedString(string: "\(match.line)  ", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor])
            text.append(match.preview)
            label.attributedStringValue = text
        }
        return cell
    }
}
