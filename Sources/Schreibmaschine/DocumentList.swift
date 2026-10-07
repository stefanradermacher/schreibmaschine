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

/// The document list (⌃⌘S): every open document of every window in a sidebar on the left, in
/// the order of Window → Documents, with a dot for unsaved changes. A click brings the document
/// to the front. Shown or hidden for all windows at once.
final class DocumentListView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    static let didChange = Notification.Name("DocumentListDidChange")

    /// Asks every list to show the documents again, after a change the list cannot observe itself.
    static func setNeedsUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async {
            updateScheduled = false
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
    private static var updateScheduled = false

    final class Group {
        let title: String
        var entries: [Entry]
        init(title: String, entries: [Entry]) {
            self.title = title
            self.entries = entries
        }
    }

    final class Entry {
        weak var window: NSWindow?
        weak var document: TextDocument?
        init(window: NSWindow, document: TextDocument) {
            self.window = window
            self.document = document
        }
    }

    private let outline = NSOutlineView()
    private var groups: [Group] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: String(localized: "Offene Dokumente"))
        title.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Schließen"))!,
                             target: self, action: #selector(hideList(_:)))
        close.isBordered = false
        close.toolTip = String(localized: "Dokumentliste ausblenden")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("document"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.floatsGroupRows = false
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
        header.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 4, right: 8)
        let separator = NSBox()
        separator.boxType = .separator
        for view in [header, scroll, separator] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: separator.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: separator.leadingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
        ])

        let center = NotificationCenter.default
        let update: (Notification) -> Void = { _ in DocumentListView.setNeedsUpdate() }
        observers = [
            center.addObserver(forName: Self.didChange, object: nil, queue: .main) { [weak self] _ in self?.update() },
            center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main, using: update),
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main, using: update),
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { update() }
    }

    override var isHidden: Bool {
        didSet { if !isHidden { update() } }
    }

    // MARK: - Content

    private func update() {
        guard !isHidden, window != nil else { return }
        let windows = DocumentNavigation.windows
        var byGroup: [(key: ObjectIdentifier, entries: [Entry])] = []
        for window in windows {
            guard let document = (window.windowController as? DocumentWindowController)?.document as? TextDocument else { continue }
            let key = ObjectIdentifier(window.tabbedWindows?.first ?? window)
            if let index = byGroup.firstIndex(where: { $0.key == key }) {
                byGroup[index].entries.append(Entry(window: window, document: document))
            } else {
                byGroup.append((key, [Entry(window: window, document: document)]))
            }
        }
        groups = byGroup.indices.map { index in
            Group(title: String(localized: "Fenster \(index + 1)"), entries: byGroup[index].entries)
        }
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        // The document of this window is the selected one.
        let own = groups.flatMap(\.entries).first { $0.window === self.window }
        if let own {
            let row = outline.row(forItem: own)
            if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }
    }

    /// With one window the documents stand alone; with several, under the window they are in.
    private var showsGroups: Bool { groups.count > 1 }

    @objc private func hideList(_ sender: Any?) {
        UserDefaults.standard.set(false, forKey: Preferences.showsDocumentList)
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard let entry = outline.item(atRow: row) as? Entry, let window = entry.window else { return }
        DocumentNavigation.show(window)
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return showsGroups ? groups.count : groups.first?.entries.count ?? 0 }
        return (item as? Group)?.entries.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return showsGroups ? groups[index] : groups[0].entries[index] }
        return (item as! Group).entries[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is Group
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        item is Group
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        item is Entry
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let group = item as? Group {
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: group.title)
            cell.textField = label
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
        guard let entry = item as? Entry, let document = entry.document else { return nil }
        let cell = NSTableCellView()
        let icon = NSImageView(image: document.fileURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
                                   ?? NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)!)
        icon.imageScaling = .scaleProportionallyDown
        let label = NSTextField(labelWithString: document.displayName)
        label.lineBreakMode = .byTruncatingMiddle
        cell.textField = label
        cell.imageView = icon
        // A dot for unsaved changes, as in the tabs of Xcode.
        let dot = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: String(localized: "Ungesichert"))!)
        dot.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 6, weight: .regular)
        dot.contentTintColor = .secondaryLabelColor
        dot.isHidden = !document.isDocumentEdited
        for view in [icon, label, dot] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            dot.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 4),
            dot.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            dot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.toolTip = document.fileURL?.path ?? document.keptName
        return cell
    }
}
