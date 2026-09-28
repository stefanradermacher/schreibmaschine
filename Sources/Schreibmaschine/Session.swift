import AppKit

/// The app's own session: the windows with their tabs, and in each tab a file or an unsaved text.
///
/// The session replaces macOS window restoration, whose result depends on a system setting and
/// on how the app was quit. It is written a few seconds after every change, so it survives a
/// crash, and unsaved texts are kept as buffer files beside it: quitting never asks and never
/// loses text.
///
/// Layout in Application Support:
/// - `Session/current/session.json` and one `<id>.txt` per unsaved text: the running session
/// - `Session/previous/…`: a session that was not restored because the app was started by
///   opening a file, or because the settings say so. It stays until it is restored or discarded.
struct SessionData: Codable {
    var windows: [WindowData] = []
    /// False while the app runs; true after a normal quit. False at launch means a crash.
    var cleanExit = false

    var isEmpty: Bool { windows.isEmpty }
    var unsavedCount: Int { windows.reduce(0) { $0 + $1.tabs.filter(\.hasBuffer).count } }
}

struct WindowData: Codable {
    var frame: String
    var tabs: [TabData]
    var selectedTab: Int
}

struct TabData: Codable {
    var id: UUID
    /// Security-scoped bookmark of the file; nil for a text that was never saved.
    var bookmark: Data?
    var path: String?
    var name: String
    /// Name of a text without file that came from a file which is gone.
    var keptName: String?
    /// The text has changes that are not in the file; they are in `<id>.txt`.
    var hasBuffer: Bool
    var encoding: UInt
    var hasBOM: Bool
    var lineEnding: String
    var view: ViewState?
}

final class SessionStore {
    static let shared = SessionStore()

    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Schreibmaschine", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    private let currentDirectory = supportDirectory.appendingPathComponent("Session/current", isDirectory: true)
    private let previousDirectory = supportDirectory.appendingPathComponent("Session/previous", isDirectory: true)

    /// Posted when the session was written or the previous session changed; the Session menu listens.
    static let didChange = Notification.Name("SessionStoreDidChange")

    /// While restoring, windows are placed from the session and not saved in between.
    private(set) var isRestoring = false
    /// After the session was written for quitting, closing windows must not overwrite it.
    private(set) var isQuitting = false
    private var saveScheduled = false
    /// The last session written, for the Session menu.
    private(set) var current = SessionData()

    private init() {
        for directory in [currentDirectory, previousDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Reading and writing

    private func read(from directory: URL) -> SessionData? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("session.json")) else { return nil }
        return try? JSONDecoder().decode(SessionData.self, from: data)
    }

    private func write(_ session: SessionData, to directory: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: directory.appendingPathComponent("session.json"), options: .atomic)
    }

    var previous: SessionData? {
        guard let session = read(from: previousDirectory), !session.isEmpty else { return nil }
        return session
    }

    /// Writes the session a moment later; many changes in a row cause one write.
    func setNeedsSave() {
        guard !saveScheduled, !isRestoring, !isQuitting else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            if saveScheduled { save() }
        }
    }

    /// Writes the session and the unsaved texts now.
    @discardableResult
    func save(cleanExit: Bool = false) -> Bool {
        saveScheduled = false
        guard !isQuitting else { return true }
        var session = capture()
        session.cleanExit = cleanExit
        var ok = true
        var keep: Set<String> = ["session.json"]
        for window in session.windows {
            for tab in window.tabs where tab.hasBuffer {
                keep.insert("\(tab.id.uuidString).txt")
            }
        }
        for document in NSDocumentController.shared.documents.compactMap({ $0 as? TextDocument }) {
            if document.needsBuffer {
                do {
                    try Data(document.textStorage.string.utf8).write(to: bufferURL(document.sessionID, in: currentDirectory), options: .atomic)
                } catch {
                    ok = false
                }
            }
            if let fileURL = document.fileURL, let view = document.editor?.viewState {
                FileStateStore.shared.record(view, for: fileURL)
            }
        }
        write(session, to: currentDirectory)
        // Buffers of texts that were saved or closed in the meantime go.
        for name in (try? FileManager.default.contentsOfDirectory(atPath: currentDirectory.path)) ?? [] where !keep.contains(name) {
            try? FileManager.default.removeItem(at: currentDirectory.appendingPathComponent(name))
        }
        current = session
        if cleanExit && ok {
            isQuitting = true
            // Still running a few seconds later: quitting was cancelled, for instance by another
            // app during logout. Then the session goes on being saved.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
                isQuitting = false
                save()
            }
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
        return ok
    }

    private func bufferURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).txt")
    }

    // MARK: - Capturing

    /// The document windows from front to back, each tab group once, its tabs in their order.
    func capture() -> SessionData {
        var session = SessionData()
        var seen = Set<ObjectIdentifier>()
        for window in NSApp.orderedWindows where window.windowController is DocumentWindowController {
            let group = window.tabbedWindows ?? [window]
            guard seen.insert(ObjectIdentifier(group.first!)).inserted else { continue }
            let tabs = group.compactMap { tab($0) }
            guard !tabs.isEmpty else { continue }
            let selected = group.firstIndex { $0 == window.tabGroup?.selectedWindow } ?? 0
            session.windows.append(WindowData(frame: NSStringFromRect(window.frame), tabs: tabs, selectedTab: min(selected, tabs.count - 1)))
        }
        return session
    }

    private func tab(_ window: NSWindow) -> TabData? {
        guard let controller = window.windowController as? DocumentWindowController,
              let document = controller.document as? TextDocument
        else { return nil }
        // An empty, untouched new document is not worth restoring.
        if document.fileURL == nil && !document.needsBuffer { return nil }
        return TabData(
            id: document.sessionID,
            bookmark: document.bookmark,
            path: document.fileURL?.path,
            name: document.displayName,
            keptName: document.keptName,
            hasBuffer: document.needsBuffer,
            encoding: document.encoding.rawValue,
            hasBOM: document.hasBOM,
            lineEnding: document.lineEnding.rawValue,
            view: controller.editor?.viewState)
    }

    // MARK: - At launch

    /// What happens to the stored session when the app starts. `restore` is false when the app
    /// was started by opening a file, or when the settings say not to restore; after a crash
    /// the session comes back anyway, unless files were opened.
    func launch(openedFiles: Bool) {
        guard let stored = read(from: currentDirectory), !stored.isEmpty else { return }
        let crashed = !stored.cleanExit
        let wanted = Preferences.startupActionValue == .restoreSession
        if !openedFiles && (wanted || crashed) {
            restore(stored, from: currentDirectory)
        } else {
            keepAsPrevious(stored)
        }
    }

    /// Moves the stored session aside as the previous session. A previous session with unsaved
    /// texts is kept, and the stored one is added to it, so no text is ever dropped.
    private func keepAsPrevious(_ stored: SessionData) {
        let fileManager = FileManager.default
        var previous = read(from: previousDirectory) ?? SessionData()
        if previous.unsavedCount == 0 {
            try? fileManager.removeItem(at: previousDirectory)
            try? fileManager.createDirectory(at: previousDirectory, withIntermediateDirectories: true)
            previous = SessionData()
        }
        previous.windows += stored.windows
        previous.cleanExit = true
        for window in stored.windows {
            for tab in window.tabs where tab.hasBuffer {
                let target = bufferURL(tab.id, in: previousDirectory)
                try? fileManager.removeItem(at: target)
                try? fileManager.moveItem(at: bufferURL(tab.id, in: currentDirectory), to: target)
            }
        }
        write(previous, to: previousDirectory)
        write(SessionData(), to: currentDirectory)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    /// Opens the previous session in addition to what is open now, then forgets it.
    func restorePrevious() {
        guard let previous else { return }
        restore(previous, from: previousDirectory)
        save()
        discardPrevious()
    }

    func discardPrevious() {
        try? FileManager.default.removeItem(at: previousDirectory)
        try? FileManager.default.createDirectory(at: previousDirectory, withIntermediateDirectories: true)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    // MARK: - Restoring

    private func restore(_ session: SessionData, from directory: URL) {
        isRestoring = true
        var missing: [String] = []
        // Back to front, so the front window ends up in front again.
        for window in session.windows.reversed() {
            var windows: [NSWindow] = []
            for tab in window.tabs {
                switch restoreTab(tab, from: directory) {
                case .restored(let restored): windows.append(restored)
                case .missing(let name, let restored):
                    missing.append(name)
                    if let restored { windows.append(restored) }
                case .failed: break
                }
            }
            guard let first = windows.first else { continue }
            let frame = NSRectFromString(window.frame)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                first.setFrame(frame, display: false)
            } else {
                DocumentWindowController.center(first)
            }
            DocumentWindowController.withoutAutomaticTabbing(first) { first.orderFront(nil) }
            // Each tab goes behind the one before, so the order stays as it was.
            var previousTab = first
            for other in windows.dropFirst() {
                previousTab.addTabbedWindow(other, ordered: .above)
                previousTab = other
            }
            let selected = windows[min(max(window.selectedTab, 0), windows.count - 1)]
            selected.makeKeyAndOrderFront(nil)
        }
        isRestoring = false
        if !missing.isEmpty {
            DispatchQueue.main.async { Self.reportMissing(missing) }
        }
    }

    private enum TabResult {
        case restored(NSWindow)
        /// The file is gone; with unsaved changes the text comes back as an untitled document.
        case missing(String, NSWindow?)
        case failed
    }

    private func restoreTab(_ tab: TabData, from directory: URL) -> TabResult {
        let controller = NSDocumentController.shared
        let buffer = tab.hasBuffer ? (try? String(contentsOf: bufferURL(tab.id, in: directory), encoding: .utf8)) : nil
        var document: TextDocument?
        var isMissing = false

        if let bookmark = tab.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                let accessing = url.startAccessingSecurityScopedResource()
                if let existing = controller.document(for: url) as? TextDocument {
                    // Already open, for instance from the previous session.
                    if accessing { url.stopAccessingSecurityScopedResource() }
                    return existing.windowControllers.first?.window.map { .restored($0) } ?? .failed
                }
                if let opened = try? controller.makeDocument(withContentsOf: url, ofType: controller.typeForContents(of: url)) as? TextDocument {
                    opened.adoptSecurityScope(of: url, accessing: accessing)
                    document = opened
                } else if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            isMissing = document == nil
        }

        if document == nil {
            // A text never saved, or a file that is gone but whose changes were kept.
            guard buffer != nil, let untitled = try? controller.makeUntitledDocument(ofType: controller.defaultType ?? "public.plain-text") as? TextDocument else {
                return isMissing ? .missing(tab.name, nil) : .failed
            }
            if let name = isMissing ? tab.name : tab.keptName { untitled.keptName = name }
            document = untitled
        }
        guard let document else { return .failed }

        document.sessionID = tab.id
        if let buffer {
            document.restore(text: buffer,
                             encoding: String.Encoding(rawValue: tab.encoding),
                             hasBOM: tab.hasBOM,
                             lineEnding: LineEnding(rawValue: tab.lineEnding) ?? .lf)
        }
        controller.addDocument(document)
        document.makeWindowControllers()
        guard let windowController = document.windowControllers.first as? DocumentWindowController,
              let window = windowController.window
        else { return .failed }
        if let view = tab.view { windowController.editor?.pendingViewState = view }
        return isMissing ? .missing(tab.name, window) : .restored(window)
    }

    private static func reportMissing(_ names: [String]) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Nicht alle Dateien der Sitzung sind noch da.")
        alert.informativeText = String(localized: "Diese Dateien wurden gelöscht oder verschoben: \(names.joined(separator: ", ")). Hatten sie ungesicherte Änderungen, sind diese als neue Dokumente geöffnet.")
        alert.runModal()
    }
}
