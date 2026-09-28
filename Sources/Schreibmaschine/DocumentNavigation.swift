import AppKit

/// Moving between the open documents by keyboard, across tabs and windows: ⌥⌘← and ⌥⌘→ go to
/// the previous and next document, ⌘1 to ⌘8 straight to one of the first eight, ⌘9 to the last.
/// ⌃⇥ and ⌃⇧⇥ stay what they are on every Mac: the tabs of one window.
enum DocumentNavigation {
    /// The document windows in a fixed order: windows in the order they were opened, within a
    /// window its tabs from left to right. The same order as in Window → Documents.
    static var windows: [NSWindow] {
        var groups: [[NSWindow]] = []
        var seen = Set<ObjectIdentifier>()
        for window in NSApp.windows where window.windowController is DocumentWindowController {
            let group = window.tabbedWindows ?? [window]
            guard let first = group.first, seen.insert(ObjectIdentifier(first)).inserted else { continue }
            groups.append(group)
        }
        groups.sort { ($0.map(\.windowNumber).min() ?? 0) < ($1.map(\.windowNumber).min() ?? 0) }
        return groups.flatMap { $0 }
    }

    static func show(_ window: NSWindow) {
        if let group = window.tabGroup, group.windows.count > 1 {
            group.selectedWindow = window
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// The next or previous document after the one in front, wrapping around at the ends.
    static func step(by offset: Int) {
        let windows = self.windows
        guard !windows.isEmpty else { return NSSound.beep() }
        let current = NSApp.mainWindow.flatMap { main in windows.firstIndex { $0 === main } } ?? 0
        show(windows[((current + offset) % windows.count + windows.count) % windows.count])
    }

    static func title(of window: NSWindow) -> String {
        ((window.windowController as? DocumentWindowController)?.document as? NSDocument)?.displayName ?? window.title
    }
}

/// Window → Documents: every open document in order, the first eight with ⌘1 to ⌘8 and the
/// last with ⌘9, as for tabs in Safari.
final class DocumentsMenu: NSObject, NSMenuDelegate {
    static let shared = DocumentsMenu()

    // NSMenu asks for the items also when matching key equivalents, so ⌘1 to ⌘9 always
    // refer to the documents open at that moment.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let windows = DocumentNavigation.windows
        if windows.isEmpty {
            let empty = NSMenuItem(title: String(localized: "Keine Dokumente"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (index, window) in windows.enumerated() {
            let isLast = index == windows.count - 1
            let key = index < 8 ? String(index + 1) : isLast ? "9" : ""
            menu.addItem(item(for: window, key: key))
        }
        // ⌘9 is the last document even when it already has a lower number; hidden items keep
        // their key equivalents.
        if let last = windows.last, windows.count < 9 {
            let item = item(for: last, key: "9")
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
            menu.addItem(item)
        }
    }

    private func item(for window: NSWindow, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: DocumentNavigation.title(of: window), action: #selector(show(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = .command
        item.target = self
        item.representedObject = window
        item.state = window === NSApp.mainWindow ? .on : .off
        return item
    }

    @objc private func show(_ sender: NSMenuItem) {
        if let window = sender.representedObject as? NSWindow { DocumentNavigation.show(window) }
    }
}
