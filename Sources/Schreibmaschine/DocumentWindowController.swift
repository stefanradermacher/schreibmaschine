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
        shouldCascadeWindows = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var document: AnyObject? {
        didSet {
            guard let document = document as? TextDocument, contentViewController == nil, let window else { return }
            let size = window.contentRect(forFrameRect: window.frame).size
            contentViewController = EditorViewController(document: document)
            window.setContentSize(size)
        }
    }

    var editor: EditorViewController? { contentViewController as? EditorViewController }

    /// Opens the window as a tab of the front document window if the settings want that.
    override func showWindow(_ sender: Any?) {
        guard let window, !window.isVisible else { return super.showWindow(sender) }
        if UserDefaults.standard.bool(forKey: Preferences.opensDocumentsInTabs), let host = Self.frontDocumentWindow(excluding: window) {
            host.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(sender)
        } else {
            super.showWindow(sender)
        }
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
    }

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
