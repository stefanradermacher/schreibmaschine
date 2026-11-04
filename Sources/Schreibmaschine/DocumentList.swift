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
final class DocumentListView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
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
        outline.menu = NSMenu()
        outline.menu?.delegate = self
        outline.registerForDraggedTypes([.fileURL])
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

    /// Files dragged onto the list open as documents; the whole list is the target.
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return FileDrop.operation(info)
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        FileDrop.open(info)
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
        let cell = EntryCell(document: document)
        cell.onClose = { DocumentCloser.close([document]) }
        return cell
    }

    // MARK: - Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let entry = outline.item(atRow: outline.clickedRow) as? Entry, let document = entry.document else { return }
        let others = groups.flatMap(\.entries).compactMap(\.document).filter { $0 !== document }
        func add(_ title: String, enabled: Bool = true, _ action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: enabled ? #selector(ClosureItem.run(_:)) : nil, keyEquivalent: "")
            let target = ClosureItem(action)
            item.target = target
            item.representedObject = target
            menu.addItem(item)
        }
        add(String(localized: "Schließen")) { DocumentCloser.close([document]) }
        add(String(localized: "Andere schließen"), enabled: !others.isEmpty) { DocumentCloser.close(others) }
        menu.addItem(.separator())
        let url = document.fileURL
        add(String(localized: "Im Finder zeigen"), enabled: url != nil) {
            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        add(String(localized: "Pfad kopieren"), enabled: url != nil) {
            guard let url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
    }
}

/// A menu item's action as a closure; the item keeps it alive.
private final class ClosureItem: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run(_ sender: Any?) { action() }
}

/// A document in the list: icon, name, and a dot for unsaved changes, which gives way to a
/// close button while the mouse is over the row, as in the tabs of Safari and Xcode.
private final class EntryCell: NSTableCellView {
    var onClose: (() -> Void)?
    private let dot = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: String(localized: "Ungesichert"))!)
    private let close = NSButton()
    private let isEdited: Bool
    private var isHovered = false { didSet { updateMarks() } }

    init(document: TextDocument) {
        isEdited = document.isDocumentEdited
        super.init(frame: .zero)
        let icon = NSImageView(image: document.fileURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
                                   ?? NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)!)
        icon.imageScaling = .scaleProportionallyDown
        let label = NSTextField(labelWithString: document.displayName)
        label.lineBreakMode = .byTruncatingMiddle
        textField = label
        imageView = icon
        dot.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 6, weight: .regular)
        dot.contentTintColor = .secondaryLabelColor
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Schließen"))
        close.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.toolTip = String(localized: "Dokument schließen")
        close.target = self
        close.action = #selector(closeClicked(_:))
        for view in [icon, label, dot, close] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -4),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 16),
            close.heightAnchor.constraint(equalToConstant: 16),
            dot.centerXAnchor.constraint(equalTo: close.centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toolTip = document.fileURL?.path ?? document.keptName
        updateMarks()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateMarks() {
        close.isHidden = !isHovered
        dot.isHidden = isHovered || !isEdited
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        // A row that appears under the mouse, by scrolling or after an update, is hovered too.
        if let window { isHovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    @objc private func closeClicked(_ sender: Any?) { onClose?() }
}

/// Closes documents one after another, each as ⌘W in its tab would: with the question about
/// unsaved changes, on the document's window, brought to the front for it. Cancel stops the
/// rest. It outlives the list, whose window may be among those that close.
enum DocumentCloser {
    private static var queue: [TextDocument] = []
    private static let delegate = Delegate()

    static func close(_ documents: [TextDocument]) {
        queue = documents
        closeNext()
    }

    private static func closeNext() {
        guard !queue.isEmpty else { return }
        let document = queue.removeFirst()
        if document.isDocumentEdited, let window = document.windowControllers.first?.window {
            DocumentNavigation.show(window)
        }
        document.canClose(withDelegate: delegate, shouldClose: #selector(Delegate.document(_:shouldClose:contextInfo:)), contextInfo: nil)
    }

    private final class Delegate: NSObject {
        @objc func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
            guard shouldClose else { return DocumentCloser.queue.removeAll() }
            document.close()
            DispatchQueue.main.async { DocumentCloser.closeNext() }
        }
    }
}
