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

/// The window of a document. New documents open as a tab in the front window or in a window
/// of their own, as the settings say.
final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    static let tabbingIdentifier = "Schreibmaschine.Dokument"

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.savedContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: true)
        window.minSize = NSSize(width: 320, height: 200)
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.tabbingMode = .automatic
        // The app keeps its own session (milestone 2); macOS window restoration would reopen
        // old windows even when the app is started by opening a single file.
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self
        // Placement is done in showWindow: centered, or offset from the front window.
        shouldCascadeWindows = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var document: AnyObject? {
        didSet {
            guard let document = document as? TextDocument, contentViewController == nil, let window else { return }
            let size = window.contentRect(forFrameRect: window.frame).size
            let editor = EditorViewController(document: document)
            if let fileURL = document.fileURL {
                editor.pendingViewState = FileStateStore.shared.viewState(for: fileURL)
            }
            contentViewController = editor
            window.setContentSize(size)

        }
    }

    var editor: EditorViewController? { contentViewController as? EditorViewController }

    /// Opens the window as a tab of the front document window if the settings want that;
    /// otherwise a little below and to the right of the front window, or in the middle of the
    /// screen if there is none.
    override func showWindow(_ sender: Any?) {
        guard let window, !window.isVisible else { return super.showWindow(sender) }
        let host = Self.frontDocumentWindow(excluding: window)
        if UserDefaults.standard.bool(forKey: Preferences.opensDocumentsInTabs), let host {
            host.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(sender)
            return
        }
        if let host, Self.fillsScreen(window) {
            // A window that fills the screen stays in place: offset, it would be cut off or shrunk.
            window.setFrame((host.screen ?? NSScreen.main)?.visibleFrame ?? window.frame, display: false)
        } else if let host {
            let topLeft = NSPoint(x: host.frame.minX, y: host.frame.maxY)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: topLeft))
        } else {
            Self.center(window)
        }
        Self.withoutAutomaticTabbing(window) { super.showWindow(sender) }
    }

    /// Shows a window as a window of its own. With "Prefer tabs: Always" in the system settings,
    /// macOS would add every new window to the front one as a tab; the app decides that itself.
    /// Merging windows by hand keeps working.
    static func withoutAutomaticTabbing(_ window: NSWindow, _ show: () -> Void) {
        window.tabbingMode = .disallowed
        show()
        window.tabbingMode = .automatic
    }

    /// Whether the window takes up the whole usable area of the screen, as after zooming.
    static func fillsScreen(_ window: NSWindow) -> Bool {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return false }
        return window.frame.width >= visible.width - 2 && window.frame.height >= visible.height - 2
    }

    /// Centers the window on the screen in use. NSWindow.center() puts it higher than the middle.
    static func center(_ window: NSWindow) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return window.center() }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
        window.setFrame(frame, display: false)
    }

    private static func frontDocumentWindow(excluding window: NSWindow) -> NSWindow? {
        NSApp.orderedWindows.first { candidate in
            candidate !== window && candidate.isVisible && !candidate.isMiniaturized
                && candidate.windowController is DocumentWindowController
        }
    }

    /// The + button in the tab bar.
    override func newWindowForTab(_ sender: Any?) {
        guard let window,
              let document = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(false),
              let controller = document.windowControllers.first ?? { document.makeWindowControllers(); return document.windowControllers.first }(),
              let newWindow = controller.window
        else { return }
        window.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(sender)
    }

    // MARK: - NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (document as? NSDocument)?.undoManager
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window else { return }
        let size = window.contentRect(forFrameRect: window.frame).size
        UserDefaults.standard.set(Double(size.width), forKey: Preferences.windowWidth)
        UserDefaults.standard.set(Double(size.height), forKey: Preferences.windowHeight)
        SessionStore.shared.setNeedsSave()
    }

    // Position, order and tabs of the windows belong to the session.
    func windowDidMove(_ notification: Notification) { SessionStore.shared.setNeedsSave() }
    func windowDidBecomeMain(_ notification: Notification) { SessionStore.shared.setNeedsSave() }

    /// The size of the window last resized, or room for about 100 columns and 40 lines.
    private static var savedContentSize: NSSize {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: Preferences.windowWidth)
        let height = defaults.double(forKey: Preferences.windowHeight)
        if width >= 320, height >= 200 { return NSSize(width: width, height: height) }
        let font = Preferences.font
        return NSSize(
            width: ceil(EditorStyle.spaceWidth(of: font) * 100 + 60),
            height: ceil(NSLayoutManager().defaultLineHeight(for: font) * 40 + 36))
    }
}

