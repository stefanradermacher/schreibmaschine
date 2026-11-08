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

/// The inspector (⌥⌘0): a sidebar on the right with information about the document, the text,
/// and the character at the insertion point, or with the outline of the document. Shown or
/// hidden for all windows at once, like the document list.
final class InspectorView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    enum Tab: String { case info, outline }

    weak var editor: EditorViewController?

    private let tabs = NSSegmentedControl()
    private let infoScroll = NSScrollView()
    private let infoStack = NSStackView()
    private let outlineView = NSView()
    private let filterField = NSSearchField()
    private let table = NSTableView()
    private var items: [OutlineItem] = []
    private var shownItems: [OutlineItem] = []
    private var isSelectingProgrammatically = false
    private var pendingInfo: DispatchWorkItem?
    private var pendingOutline: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    private var tab: Tab {
        get { Tab(rawValue: UserDefaults.standard.string(forKey: Preferences.inspectorTab) ?? "") ?? .info }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Preferences.inspectorTab) }
    }

    init() {
        super.init(frame: .zero)

        tabs.segmentStyle = .automatic
        tabs.trackingMode = .selectOne
        tabs.segmentCount = 2
        tabs.setImage(NSImage(systemSymbolName: "info.circle", accessibilityDescription: String(localized: "Informationen")), forSegment: 0)
        tabs.setImage(NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: String(localized: "Gliederung")), forSegment: 1)
        tabs.setToolTip(String(localized: "Informationen"), forSegment: 0)
        tabs.setToolTip(String(localized: "Gliederung"), forSegment: 1)
        tabs.target = self
        tabs.action = #selector(tabChanged(_:))

        // Information: sections of label and value, scrolling if the window is low.
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 14
        infoStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 16, right: 14)
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(infoStack)
        infoScroll.documentView = document
        infoScroll.drawsBackground = false
        infoScroll.hasVerticalScroller = true
        infoScroll.autohidesScrollers = true
        NSLayoutConstraint.activate([
            infoStack.topAnchor.constraint(equalTo: document.topAnchor),
            infoStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            infoStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            infoStack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: infoScroll.contentView.widthAnchor),
        ])

        // Outline: a filter and the entries, indented by level.
        filterField.placeholderString = String(localized: "Filtern")
        filterField.controlSize = .small
        filterField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        filterField.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .inset
        table.backgroundColor = .clear
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked(_:))
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.drawsBackground = false
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true
        let empty = NSTextField(wrappingLabelWithString: String(localized: "Für diese Sprache gibt es keine Gliederung."))
        empty.textColor = .secondaryLabelColor
        empty.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        empty.alignment = .center
        empty.identifier = NSUserInterfaceItemIdentifier("empty")
        for view in [filterField, tableScroll, empty] {
            view.translatesAutoresizingMaskIntoConstraints = false
            outlineView.addSubview(view)
        }
        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: outlineView.topAnchor, constant: 10),
            filterField.leadingAnchor.constraint(equalTo: outlineView.leadingAnchor, constant: 10),
            filterField.trailingAnchor.constraint(equalTo: outlineView.trailingAnchor, constant: -10),
            tableScroll.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 8),
            tableScroll.leadingAnchor.constraint(equalTo: outlineView.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: outlineView.trailingAnchor),
            tableScroll.bottomAnchor.constraint(equalTo: outlineView.bottomAnchor),
            empty.centerYAnchor.constraint(equalTo: outlineView.centerYAnchor),
            empty.leadingAnchor.constraint(equalTo: outlineView.leadingAnchor, constant: 20),
            empty.trailingAnchor.constraint(equalTo: outlineView.trailingAnchor, constant: -20),
        ])

        let header = NSView()
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Schließen"))!,
                             target: self, action: #selector(hideInspector(_:)))
        close.isBordered = false
        close.toolTip = String(localized: "Inspektor ausblenden")
        let separator = NSBox()
        separator.boxType = .separator
        let edge = NSBox()
        edge.boxType = .separator
        for view in [header, tabs, close, separator, infoScroll, outlineView, edge] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            edge.topAnchor.constraint(equalTo: topAnchor),
            edge.bottomAnchor.constraint(equalTo: bottomAnchor),
            edge.leadingAnchor.constraint(equalTo: leadingAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: edge.trailingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 34),
            tabs.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            tabs.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            close.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: edge.trailingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
        for view in [infoScroll, outlineView] {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: separator.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: edge.trailingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        showTab()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func hideInspector(_ sender: Any?) {
        UserDefaults.standard.set(false, forKey: Preferences.showsInspector)
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.intersection(dirtyRect).fill()
    }

    /// Connects to the editor's document; called once by the editor.
    func attach(to editor: EditorViewController) {
        self.editor = editor
        let document = editor.document
        let center = NotificationCenter.default
        let refresh: (Notification) -> Void = { [weak self] _ in self?.documentDidChange() }
        observers = [
            center.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: document.textStorage, queue: .main) { [weak self] _ in
                guard document.textStorage.editedMask.contains(.editedCharacters) else { return }
                self?.documentDidChange()
            },
            center.addObserver(forName: TextDocument.formatDidChange, object: document, queue: .main, using: refresh),
            center.addObserver(forName: TextDocument.languageDidChange, object: document, queue: .main, using: refresh),
            center.addObserver(forName: TextDocument.indentationDidChange, object: document, queue: .main, using: refresh),
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, note.object as? NSWindow === window else { return }
                documentDidChange()
            },
        ]
    }

    override var isHidden: Bool {
        didSet { if !isHidden { documentDidChange() } }
    }

    // MARK: - Updating

    /// After an edit, a change of format, or saving: everything anew, a moment later.
    func documentDidChange() {
        scheduleInfo()
        scheduleOutline()
    }

    /// The insertion point moved: the character and the current entry of the outline.
    func selectionDidChange() {
        scheduleInfo(delay: 0.05)
        selectCurrentItem()
    }

    private func scheduleInfo(delay: TimeInterval = 0.25) {
        guard !isHidden, tab == .info else { return }
        pendingInfo?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateInfo() }
        pendingInfo = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleOutline() {
        guard !isHidden, tab == .outline else { return }
        pendingOutline?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateOutline() }
        pendingOutline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    @objc private func tabChanged(_ sender: Any?) {
        tab = tabs.selectedSegment == 1 ? .outline : .info
        showTab()
    }

    private func showTab() {
        tabs.selectedSegment = tab == .outline ? 1 : 0
        infoScroll.isHidden = tab != .info
        outlineView.isHidden = tab != .outline
        documentDidChange()
    }

    // MARK: - Information

    private func updateInfo() {
        guard let editor else { return }
        let document = editor.document
        let textView = editor.textView
        let text = document.textStorage.string
        infoStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // The file.
        var file: [(String, String)] = []
        if let url = document.fileURL {
            file.append((String(localized: "Name"), url.lastPathComponent))
            file.append((String(localized: "Ort"), (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath))
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isWritableKey])
            if let size = values?.fileSize {
                file.append((String(localized: "Größe"), ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
            }
            if let date = values?.creationDate {
                file.append((String(localized: "Erstellt"), date.formatted(date: .abbreviated, time: .shortened)))
            }
            if let date = values?.contentModificationDate {
                file.append((String(localized: "Geändert"), date.formatted(date: .abbreviated, time: .shortened)))
            }
            if values?.isWritable == false {
                file.append((String(localized: "Zugriff"), String(localized: "nur lesen")))
            }
        } else {
            file.append((String(localized: "Name"), document.displayName))
            file.append((String(localized: "Ort"), String(localized: "noch nicht gesichert")))
        }
        addSection(String(localized: "Datei"), rows: file, revealsFile: document.fileURL)

        // The text.
        let statistics = TextStatistics(of: text)
        let indentation = document.indentation
        let bytes = text.data(using: document.encoding, allowLossyConversion: true)?.count ?? text.utf8.count
        var rows: [(String, String)] = [
            (String(localized: "Sprache"), document.language?.name ?? String(localized: "Reiner Text")),
            (String(localized: "Kodierung"), TextEncoding.name(of: document.encoding) + (document.hasBOM ? String(localized: " mit BOM") : "")),
            (String(localized: "Zeilenenden"), document.lineEnding.name),
            (String(localized: "Einrückung"), indentation.usesSpaces
                ? String(localized: "\(indentation.width) Leerzeichen") : String(localized: "Tabs, Breite \(indentation.width)")),
            (String(localized: "Zeilen"), statistics.lines.formatted()),
            (String(localized: "Wörter"), statistics.words.formatted()),
            (String(localized: "Zeichen"), statistics.characters.formatted()),
            (String(localized: "Bytes"), bytes.formatted()),
        ]
        // Reading at about 200 words a minute.
        if statistics.words >= 50 {
            let minutes = max(1, Int((Double(statistics.words) / 200).rounded()))
            rows.append((String(localized: "Lesedauer"), minutes == 1 ? String(localized: "etwa 1 Minute") : String(localized: "etwa \(minutes) Minuten")))
        }
        addSection(String(localized: "Text"), rows: rows)

        // The selection.
        let selections = textView.editingRanges.filter { $0.length > 0 }
        if !selections.isEmpty {
            let selected = selections.map { (text as NSString).substring(with: $0) }.joined(separator: "\n")
            let part = TextStatistics(of: selected)
            addSection(String(localized: "Auswahl"), rows: [
                (String(localized: "Zeilen"), part.lines.formatted()),
                (String(localized: "Wörter"), part.words.formatted()),
                (String(localized: "Zeichen"), part.characters.formatted()),
            ])
        }

        // The character at the insertion point, or the one selected.
        addCharacterSection(textView: textView, encoding: document.encoding)
    }

    private func addSection(_ title: String, rows: [(String, String)], revealsFile url: URL? = nil) {
        let heading = NSTextField(labelWithString: title)
        heading.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        heading.textColor = .secondaryLabelColor
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 4
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        for (label, value) in rows {
            let name = NSTextField(labelWithString: label)
            name.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            name.textColor = .secondaryLabelColor
            let content = NSTextField(wrappingLabelWithString: value)
            content.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            content.isSelectable = true
            content.preferredMaxLayoutWidth = 150
            content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            grid.addRow(with: [name, content])
        }
        var views: [NSView] = [heading, grid]
        if let url {
            let reveal = NSButton(title: String(localized: "Im Finder zeigen"), target: nil, action: nil)
            reveal.controlSize = .small
            reveal.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            reveal.bezelStyle = .push
            let action = ClosureItem { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            reveal.target = action
            reveal.action = #selector(ClosureItem.run(_:))
            objc_setAssociatedObject(reveal, &Self.actionKey, action, .OBJC_ASSOCIATION_RETAIN)
            views.append(reveal)
        }
        let section = NSStackView(views: views)
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6
        infoStack.addArrangedSubview(section)
    }

    private static var actionKey = 0

    private func addCharacterSection(textView: EditorTextView, encoding: String.Encoding) {
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        var range: NSRange?
        if selection.length > 0 {
            let first = text.rangeOfComposedCharacterSequence(at: selection.location)
            if first.length == selection.length { range = first }
        } else if selection.location < text.length {
            range = text.rangeOfComposedCharacterSequence(at: selection.location)
        }
        guard let range else { return }
        let character = text.substring(with: range)
        let scalars = Array(character.unicodeScalars)
        let shown: String
        switch character {
        case "\n": shown = "¬"
        case "\t": shown = "→"
        case " ": shown = "·"
        default: shown = character
        }
        let big = NSTextField(labelWithString: shown)
        big.font = NSFont.systemFont(ofSize: 34)
        let codes = scalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
        // Control characters have no name in Unicode, only the usual ones.
        let controls: [UInt32: String] = [0x09: "Character Tabulation (Tab)", 0x0A: "Line Feed (LF)", 0x0D: "Carriage Return (CR)",
                                          0x0C: "Form Feed (FF)", 0x0B: "Line Tabulation", 0x00: "Null", 0x1B: "Escape", 0x7F: "Delete"]
        let names = scalars.map { scalar in
            controls[scalar.value] ?? scalar.properties.name ?? scalar.properties.nameAlias ?? String(localized: "ohne Namen")
        }
            .joined(separator: ", ")
        let bytes: String
        if let data = character.data(using: encoding, allowLossyConversion: false) {
            bytes = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        } else {
            bytes = String(localized: "in \(TextEncoding.name(of: encoding)) nicht darstellbar")
        }
        addSection(String(localized: "Zeichen an der Einfügemarke"), rows: [
            (String(localized: "Codepunkt"), codes),
            (String(localized: "Name"), names.contains("(") ? names : names.capitalized(with: Locale(identifier: "en"))),
            (String(localized: "Bytes"), bytes),
        ])
        if let section = infoStack.arrangedSubviews.last as? NSStackView {
            section.insertArrangedSubview(big, at: 1)
        }
    }

    // MARK: - Outline

    private func updateOutline() {
        guard let editor else { return }
        let hasRules = editor.document.language?.outline.isEmpty == false
        items = hasRules ? Outline.items(in: editor.document) : []
        outlineView.subviews.first { $0.identifier?.rawValue == "empty" }?.isHidden = hasRules
        filterField.isHidden = !hasRules
        applyFilter()
    }

    private func applyFilter() {
        let query = filterField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        shownItems = query.isEmpty ? items : items.filter { $0.name.lowercased().contains(query) }
        table.reloadData()
        selectCurrentItem()
    }

    func controlTextDidChange(_ notification: Notification) { applyFilter() }

    /// The entry the insertion point is in stays selected and in view.
    private func selectCurrentItem() {
        guard !isHidden, tab == .outline, let editor else { return }
        let caret = editor.textView.selectedRange().location
        guard let index = shownItems.lastIndex(where: { $0.location <= caret }) else {
            table.deselectAll(nil)
            return
        }
        guard table.selectedRow != index else { return }
        isSelectingProgrammatically = true
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
        isSelectingProgrammatically = false
    }

    /// A click on the entry that is selected already goes there again.
    @objc private func rowClicked(_ sender: Any?) {
        guard table.clickedRow >= 0, table.clickedRow == table.selectedRow else { return }
        reveal(row: table.clickedRow, focus: true)
    }

    /// Choosing an entry, with the mouse or the arrow keys, goes there.
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSelectingProgrammatically else { return }
        reveal(row: table.selectedRow, focus: NSApp.currentEvent?.type == .leftMouseUp || NSApp.currentEvent?.type == .leftMouseDown)
    }

    private func reveal(row: Int, focus: Bool) {
        guard shownItems.indices.contains(row), let editor else { return }
        editor.reveal(shownItems[row])
        // With the arrow keys the list keeps the focus, so the next entry is one key away.
        if focus { window?.makeFirstResponder(editor.textView) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shownItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = shownItems[row]
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: item.name)
        label.font = item.level == 0 ? NSFont.boldSystemFont(ofSize: NSFont.systemFontSize - 1) : NSFont.systemFont(ofSize: NSFont.systemFontSize - 1)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = String(localized: "Zeile \(item.line)")
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4 + CGFloat(min(item.level, 8)) * 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// A container whose content starts at the top.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
