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

/// The command palette (⇧⌘P): every command of the menu bar, found by typing a few letters,
/// the most recently used on top. It lists what the menus offer at that moment, so encodings,
/// open documents and, later, languages and user scripts come along without extra work.
final class CommandPalette: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    static let shared = CommandPalette()

    private struct Entry {
        let item: NSMenuItem
        let title: String
        let path: String
        let shortcut: String
        var key: String { path + " › " + title }
    }

    private var panel: PalettePanel?
    private let field = NSTextField()
    private let table = NSTableView()
    private var entries: [Entry] = []
    private var shown: [Entry] = []
    private weak var targetWindow: NSWindow?
    private let recentKey = "CommandPaletteRecent"

    func show() {
        targetWindow = NSApp.mainWindow ?? NSApp.keyWindow
        // Collected while the document window is still key, so the menus validate against it.
        entries = collect(NSApp.mainMenu, path: [])
        let panel = self.panel ?? makePanel()
        self.panel = panel
        field.stringValue = ""
        filter()
        place(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    private func close() {
        panel?.orderOut(nil)
        targetWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Collecting the commands

    private func collect(_ menu: NSMenu?, path: [String]) -> [Entry] {
        guard let menu, menu !== NSApp.servicesMenu else { return [] }
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.update()
        var result: [Entry] = []
        var seen = Set<String>()
        for item in menu.items where !item.isSeparatorItem && !item.isHidden && item.isEnabled {
            // AppKit's own items, such as Clear Menu, can appear twice.
            guard seen.insert(item.title + "|" + (item.action.map(NSStringFromSelector) ?? "")).inserted else { continue }
            if let submenu = item.submenu {
                result += collect(submenu, path: path + [item.title])
            } else if let action = item.action,
                      action != #selector(AppDelegate.showCommandPalette(_:)),
                      action != #selector(NSWindow.makeKeyAndOrderFront(_:)) {
                result.append(Entry(item: item, title: item.title, path: path.joined(separator: " › "), shortcut: Self.shortcut(of: item)))
            }
        }
        return result
    }

    private static func shortcut(of item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let modifiers = item.keyEquivalentModifierMask
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        let key: String
        switch item.keyEquivalent.unicodeScalars.first.map({ Int($0.value) }) {
        case NSUpArrowFunctionKey: key = "↑"
        case NSDownArrowFunctionKey: key = "↓"
        case NSLeftArrowFunctionKey: key = "←"
        case NSRightArrowFunctionKey: key = "→"
        case Int(NSBackspaceCharacter): key = "⌫"
        case Int(NSTabCharacter): key = "⇥"
        default: key = item.keyEquivalent.uppercased()
        }
        return text + key
    }

    // MARK: - Filtering

    private var recent: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(12)), forKey: recentKey) }
    }

    private func filter() {
        let query = field.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        let recent = self.recent
        if query.isEmpty {
            let recentEntries = recent.compactMap { key in entries.first { $0.key == key } }
            shown = recentEntries + entries.filter { entry in !recent.contains(entry.key) }
        } else {
            shown = entries.compactMap { entry -> (Entry, Int)? in
                guard var score = Self.score(query, in: entry.title.lowercased()) ?? Self.score(query, in: entry.key.lowercased()).map({ $0 - 30 })
                else { return nil }
                if let index = recent.firstIndex(of: entry.key) { score += 20 - index }
                return (entry, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        }
        table.reloadData()
        if !shown.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
    }

    /// The query as a whole, or its letters in order, each either right after the previous one
    /// or at the start of a word: "zverb" finds "Zeilen verbinden", scattered letters do not count.
    /// nil if it does not match.
    private static func score(_ query: String, in candidate: String) -> Int? {
        let characters = Array(candidate)
        let isWordStart = { (index: Int) in index == 0 || !(characters[index - 1].isLetter || characters[index - 1].isNumber) }
        if let range = candidate.range(of: query) {
            let start = candidate.distance(from: candidate.startIndex, to: range.lowerBound)
            return 200 + (start == 0 ? 60 : isWordStart(start) ? 40 : 0) - characters.count / 4
        }
        // Greedy, preferring runs: continue a run if possible, else jump to the next word start.
        var score = 0
        var position = 0
        var previous: Int?
        for letter in query {
            var found: Int?
            if let previous, previous + 1 < characters.count, characters[previous + 1] == letter {
                found = previous + 1
                score += 8
            } else {
                var index = position
                while index < characters.count {
                    if characters[index] == letter && isWordStart(index) { found = index; break }
                    index += 1
                }
                score += 12
            }
            guard let found else { return nil }
            previous = found
            position = found + 1
        }
        return score - characters.count / 8
    }

    // MARK: - Running

    private func runSelected() {
        let row = table.selectedRow
        guard shown.indices.contains(row) else { return NSSound.beep() }
        let entry = shown[row]
        var recent = self.recent
        recent.removeAll { $0 == entry.key }
        recent.insert(entry.key, at: 0)
        self.recent = recent
        close()
        guard let action = entry.item.action else { return }
        // The document window is key again, so actions without target reach its text.
        NSApp.sendAction(action, to: entry.item.target, from: entry.item)
    }

    // MARK: - Panel

    private func makePanel() -> PalettePanel {
        let panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 380),
                                 styleMask: [.titled, .fullSizeContentView],
                                 backing: .buffered, defer: true)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active

        field.placeholderString = String(localized: "Befehl suchen")
        field.font = NSFont.systemFont(ofSize: 20)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.setAccessibilityLabel(String(localized: "Befehl suchen"))

        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 30
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(tableClicked(_:))
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let separator = NSBox()
        separator.boxType = .separator
        for view in [icon, field, separator, scroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            field.topAnchor.constraint(equalTo: background.topAnchor, constant: 16),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            separator.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8),
        ])
        panel.contentView = background
        return panel
    }

    /// Centered over the document window, in its upper part, like Spotlight over the screen.
    private func place(_ panel: NSPanel) {
        let area = targetWindow?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        var frame = panel.frame
        frame.origin.x = area.midX - frame.width / 2
        frame.origin.y = area.maxY - area.height * 0.18 - frame.height
        if let screen = targetWindow?.screen ?? NSScreen.main {
            frame = frame.intersection(screen.visibleFrame).size == frame.size ? frame : frame.offsetBy(dx: 0, dy: max(0, screen.visibleFrame.minY - frame.minY))
        }
        panel.setFrame(frame, display: false)
    }

    func windowDidResignKey(_ notification: Notification) {
        panel?.orderOut(nil)
    }

    // MARK: - Field

    func controlTextDidChange(_ notification: Notification) { filter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)): runSelected()
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    private func moveSelection(by offset: Int) {
        guard !shown.isEmpty else { return }
        let row = min(max(table.selectedRow + offset, 0), shown.count - 1)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func tableClicked(_ sender: Any?) {
        if table.clickedRow >= 0 { runSelected() }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = shown[row]
        let cell = NSView()
        let title = NSTextField(labelWithString: entry.title)
        title.font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1)
        title.lineBreakMode = .byTruncatingTail
        let path = NSTextField(labelWithString: entry.path)
        path.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        path.textColor = .secondaryLabelColor
        path.lineBreakMode = .byTruncatingHead
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let shortcut = NSTextField(labelWithString: entry.shortcut)
        shortcut.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        shortcut.textColor = .secondaryLabelColor
        shortcut.alignment = .right
        let check = NSImageView(image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)!)
        check.contentTintColor = .secondaryLabelColor
        check.isHidden = entry.item.state != .on
        for view in [check, title, path, shortcut] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        title.setContentHuggingPriority(.required, for: .horizontal)
        shortcut.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            check.widthAnchor.constraint(equalToConstant: 14),
            check.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            path.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 10),
            path.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            path.trailingAnchor.constraint(lessThanOrEqualTo: shortcut.leadingAnchor, constant: -10),
            shortcut.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            shortcut.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// A panel without title bar that still takes typing.
private final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
