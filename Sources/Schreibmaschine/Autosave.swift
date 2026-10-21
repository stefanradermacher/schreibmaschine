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
import CryptoKit

/// When the app writes changed files by itself. The session keeps unsaved texts in any case;
/// saving automatically is for other programs that read the file, as a compiler or git.
enum AutosaveMode: String, CaseIterable {
    /// Only ⌘S writes the file.
    case off
    /// When the window or tab loses the focus, the app goes to the background or the document closes.
    case onLeave
    /// As well after a pause in typing.
    case onLeaveAndPause

    static var current: AutosaveMode {
        AutosaveMode(rawValue: UserDefaults.standard.string(forKey: Preferences.autosave) ?? "") ?? .off
    }

    var title: String {
        switch self {
        case .off: String(localized: "Aus")
        case .onLeave: String(localized: "Beim Verlassen")
        case .onLeaveAndPause: String(localized: "Beim Verlassen und in Schreibpausen")
        }
    }

    /// Long enough not to write in the middle of a sentence, nor to make a watching server
    /// reload all the time.
    static let pause: TimeInterval = 15
}

// MARK: - Saving automatically

extension TextDocument {
    /// Whether the file may be written without asking: a file of its own that is there and
    /// writable, not changed by another program, and able to take every character.
    private var canAutosaveToFile: Bool {
        guard isDocumentEdited, let fileURL, fileType != nil, keptName == nil, externalChange == nil, !isSavingFile,
              // Not while a sheet waits for an answer, as the one of Save As.
              windowForSheet?.attachedSheet == nil,
              FileManager.default.isWritableFile(atPath: fileURL.path)
        else { return false }
        // A change by another program not yet noticed must not be overwritten; the bar asks.
        let date = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard date == fileModificationDate else {
            checkForExternalChange()
            return false
        }
        // Characters the encoding cannot take are a question for ⌘S.
        return textStorage.string.canBeConverted(to: encoding)
    }

    /// Writes the file if the setting and the document allow it; otherwise it stays changed.
    func autosaveToFile(completion: ((Bool) -> Void)? = nil) {
        guard AutosaveMode.current != .off, canAutosaveToFile, let fileURL, let fileType else {
            completion?(false)
            return
        }
        autosaveWork?.cancel()
        isAutosavingFile = true
        save(to: fileURL, ofType: fileType, for: .saveOperation) { [weak self] error in
            self?.isAutosavingFile = false
            completion?(error == nil)
        }
    }

    /// After a pause in typing, if the setting says so.
    func scheduleAutosave() {
        autosaveWork?.cancel()
        guard AutosaveMode.current == .onLeaveAndPause, fileURL != nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.autosaveToFile() }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + AutosaveMode.pause, execute: work)
    }

    /// Before quitting: written at once, since nothing waits for a save that is under way.
    func autosaveBeforeQuitting() {
        guard AutosaveMode.current != .off, canAutosaveToFile, let fileURL, let fileType else { return }
        do {
            isSavingFile = true
            defer { isSavingFile = false }
            try writeSafely(to: fileURL, ofType: fileType, for: .saveOperation)
            fileModificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            updateChangeCount(.changeCleared)
            VersionHistory.shared.record(textStorage.string, kind: .autosaved, for: fileURL, waits: true)
        } catch {
            // The session keeps the text.
        }
    }

    // Closing a changed document saves it instead of asking.
    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        let ask = { super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo) }
        guard AutosaveMode.current != .off, isDocumentEdited, fileURL != nil else { return ask() }
        autosaveToFile { [self] saved in
            guard saved, let selector = shouldCloseSelector else { return saved ? () : ask() }
            // - (void)document:(NSDocument *)document shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo
            typealias ShouldClose = @convention(c) (AnyObject, Selector, NSDocument, Bool, UnsafeMutableRawPointer?) -> Void
            let target = delegate as AnyObject
            let function = unsafeBitCast(target.method(for: selector), to: ShouldClose.self)
            function(target, selector, self, true, contextInfo)
        }
    }

    static func autosaveAll() {
        for case let document as TextDocument in NSDocumentController.shared.documents {
            document.autosaveToFile()
        }
    }
}

/// Saves when a window loses the focus: another window, another tab, another app.
final class AutosaveTrigger {
    static let shared = AutosaveTrigger()
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { notification in
                let window = notification.object as? NSWindow
                (window?.windowController?.document as? TextDocument)?.autosaveToFile()
            },
            center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
                TextDocument.autosaveAll()
            },
        ]
    }
}

// MARK: - History

/// Earlier states of files, as they were opened and written, kept in the app's container. Each
/// file has a folder named after its path, with an index and the texts named after their
/// content, so that a text that comes back is stored only once.
final class VersionHistory {
    static let shared = VersionHistory()

    enum Kind: String, Codable {
        case opened, saved, autosaved
    }

    struct Entry: Codable, Equatable {
        let id: UUID
        let date: Date
        let kind: Kind
        let hash: String
    }

    /// A stored state of a file: the folder of the file at that time and the entry in it.
    struct Version: Equatable {
        let folder: String
        let entry: Entry
    }

    private struct Index: Codable {
        var path: String
        var entries: [Entry]
    }

    /// Texts this long are not kept; the history is for writing, not for logs and dumps.
    static let maximumLength = 10_000_000
    static let maximumAge: TimeInterval = 14 * 24 * 3600
    static let lengths = [10, 20, 50]

    private let directory = SessionStore.supportDirectory.appendingPathComponent("History", isDirectory: true)
    private let queue = DispatchQueue(label: "Schreibmaschine.VersionHistory")

    static func folder(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func indexURL(_ folder: String) -> URL {
        directory.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("index.json")
    }

    private func textURL(_ folder: String, _ hash: String) -> URL {
        directory.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(hash + ".txt")
    }

    private func readIndex(_ folder: String) -> Index? {
        guard let data = try? Data(contentsOf: indexURL(folder)) else { return nil }
        return try? JSONDecoder().decode(Index.self, from: data)
    }

    private func writeIndex(_ index: Index, _ folder: String) {
        try? FileManager.default.createDirectory(at: indexURL(folder).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(index).write(to: indexURL(folder), options: .atomic)
    }

    /// Keeps a state of the file. Equal to the newest one, nothing new is kept; the version
    /// handed back is then that one.
    func record(_ text: String, kind: Kind, for url: URL, waits: Bool = false, completion: ((Version?) -> Void)? = nil) {
        let folder = Self.folder(for: url)
        let path = url.standardizedFileURL.path
        let keep = Preferences.historyLengthValue
        let protected = Self.versionsInUse()
        let work = { [self] in
            var result: Version?
            defer { if let completion { DispatchQueue.main.async { completion(result) } } }
            guard (text as NSString).length <= Self.maximumLength else { return }
            let hash = Self.hash(text)
            var index = readIndex(folder) ?? Index(path: path, entries: [])
            index.path = path
            if let newest = index.entries.last, newest.hash == hash {
                result = Version(folder: folder, entry: newest)
                return
            }
            let file = textURL(folder, hash)
            if !FileManager.default.fileExists(atPath: file.path) {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard (try? Data(text.utf8).write(to: file, options: .atomic)) != nil else { return }
            }
            let entry = Entry(id: UUID(), date: Date(), kind: kind, hash: hash)
            index.entries.append(entry)
            prune(&index, folder: folder, keep: keep, protected: protected)
            writeIndex(index, folder)
            result = Version(folder: folder, entry: entry)
        }
        if waits { queue.sync(execute: work) } else { queue.async(execute: work) }
    }

    /// Keeps the newest entries within the age limit, and those open documents refer to.
    private func prune(_ index: inout Index, folder: String, keep: Int, protected: Set<UUID>) {
        let oldest = Date().addingTimeInterval(-Self.maximumAge)
        let recent = Set(index.entries.suffix(keep).filter { $0.date >= oldest }.map(\.id))
        let removed = index.entries.filter { !recent.contains($0.id) && !protected.contains($0.id) }
        index.entries.removeAll { removed.contains($0) }
        let used = Set(index.entries.map(\.hash))
        for hash in Set(removed.map(\.hash)).subtracting(used) {
            try? FileManager.default.removeItem(at: textURL(folder, hash))
        }
    }

    /// The states of a file, oldest first.
    func versions(for url: URL) -> [Version] {
        let folder = Self.folder(for: url)
        return queue.sync { (readIndex(folder)?.entries ?? []).map { Version(folder: folder, entry: $0) } }
    }

    func text(of version: Version) -> String? {
        queue.sync {
            (try? Data(contentsOf: textURL(version.folder, version.entry.hash))).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    /// Whether the text is the one of the version, without reading it.
    func matches(_ text: String, _ version: Version) -> Bool {
        Self.hash(text) == version.entry.hash
    }

    /// A file moved or renamed takes its history along.
    func move(from oldURL: URL, to newURL: URL) {
        let old = Self.folder(for: oldURL), new = Self.folder(for: newURL)
        guard old != new else { return }
        queue.async { [self] in
            let from = directory.appendingPathComponent(old, isDirectory: true)
            let to = directory.appendingPathComponent(new, isDirectory: true)
            guard FileManager.default.fileExists(atPath: from.path), !FileManager.default.fileExists(atPath: to.path) else { return }
            try? FileManager.default.moveItem(at: from, to: to)
            if var index = readIndex(new) {
                index.path = newURL.standardizedFileURL.path
                writeIndex(index, new)
            }
        }
    }

    /// Forgets every state of the file, except the ones open documents still refer to.
    func clear(for url: URL) {
        let folder = Self.folder(for: url)
        let protected = Self.versionsInUse()
        queue.async { [self] in
            guard var index = readIndex(folder) else { return }
            prune(&index, folder: folder, keep: 0, protected: protected)
            writeIndex(index, folder)
        }
    }

    /// The states the open documents were opened with.
    private static func versionsInUse() -> Set<UUID> {
        Set(NSDocumentController.shared.documents.compactMap { ($0 as? TextDocument)?.openedVersion?.entry.id })
    }
}

extension TextDocument {
    /// Keeps the state the file was opened with, once a window shows the document: documents
    /// read only for a comparison have no history to add to.
    func recordOpenedVersion() {
        guard let fileURL, let text = openedText else { return }
        openedText = nil
        VersionHistory.shared.record(text, kind: .opened, for: fileURL) { [weak self] version in
            self?.openedVersion = version
        }
    }

    /// Keeps the state just written.
    func recordSavedVersion(automatically: Bool) {
        guard let fileURL else { return }
        VersionHistory.shared.record(textStorage.string, kind: automatically ? .autosaved : .saved, for: fileURL)
    }
}

// MARK: - Revert To

/// File → Revert To: the saved and the opened state, then the kept ones. With ⌥ each entry
/// compares instead.
final class RevertMenu: NSObject, NSMenuDelegate {
    static let shared = RevertMenu()

    private lazy var formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        // With seconds: several states can come from the same minute.
        formatter.timeStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    func menuNeedsUpdate(_ menu: NSMenu) {
        fill(menu, for: NSDocumentController.shared.currentDocument as? TextDocument)
    }

    func fill(_ menu: NSMenu, for document: TextDocument?) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: String(localized: "Zuletzt gesichert"), action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: ""))
        menu.addItem(alternate(String(localized: "Mit zuletzt gesicherter Fassung vergleichen"), #selector(EditorViewController.compareWithSaved(_:)), nil))

        let current = document?.textStorage.string
        let opened = document?.openedVersion
        let openedTitle = opened.map { String(localized: "Zuletzt geöffnet (\(formatter.string(from: $0.entry.date)))") }
            ?? String(localized: "Zuletzt geöffnet")
        menu.addItem(entry(openedTitle, opened, current: current))
        menu.addItem(alternate(String(localized: "Mit zuletzt geöffneter Fassung vergleichen"),
                               opened == nil ? nil : #selector(EditorViewController.compareWithVersion(_:)), opened))

        menu.addItem(.separator())
        let versions = document?.fileURL.map { VersionHistory.shared.versions(for: $0) } ?? []
        let others = versions.filter { $0.entry.id != opened?.entry.id }.reversed()
        if others.isEmpty {
            let empty = NSMenuItem(title: String(localized: "Keine früheren Fassungen"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for version in others {
            let date = formatter.string(from: version.entry.date)
            let title = switch version.entry.kind {
            case .opened: String(localized: "\(date) – geöffnet")
            case .saved: String(localized: "\(date) – gesichert")
            case .autosaved: String(localized: "\(date) – automatisch gesichert")
            }
            menu.addItem(entry(title, version, current: current))
            menu.addItem(alternate(String(localized: "\(date) – vergleichen"), #selector(EditorViewController.compareWithVersion(_:)), version))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Verlauf löschen …"), action: #selector(EditorViewController.clearVersionHistory(_:)), keyEquivalent: ""))
    }

    /// A state equal to the text in the window has nothing to go back to.
    private func entry(_ title: String, _ version: VersionHistory.Version?, current: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let version, let current, !VersionHistory.shared.matches(current, version) {
            item.action = #selector(EditorViewController.revertToVersion(_:))
            item.representedObject = version.entry.id
        }
        return item
    }

    private func alternate(_ title: String, _ action: Selector?, _ version: VersionHistory.Version?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.representedObject = version?.entry.id
        item.keyEquivalentModifierMask = .option
        item.isAlternate = true
        return item
    }
}

extension EditorViewController {
    private func version(for sender: NSMenuItem) -> VersionHistory.Version? {
        guard let id = sender.representedObject as? UUID else { return nil }
        if let opened = document.openedVersion, opened.entry.id == id { return opened }
        return document.fileURL.flatMap { VersionHistory.shared.versions(for: $0).first { $0.entry.id == id } }
    }

    /// Puts the text of an earlier state in place as one edit, which ⌘Z takes back.
    @objc func revertToVersion(_ sender: NSMenuItem) {
        guard let version = version(for: sender), let text = VersionHistory.shared.text(of: version) else { return NSSound.beep() }
        let current = document.textStorage.string as NSString
        let new = text as NSString
        // Only the part that differs is replaced, so that the view and the marks stay calm.
        var prefix = 0
        let shorter = min(current.length, new.length)
        while prefix < shorter, current.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < shorter - prefix,
              current.character(at: current.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        let range = NSRange(location: prefix, length: current.length - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return NSSound.beep() }
        let caret = textView.selectedRange().location
        document.textStorage.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        textView.undoManager?.setActionName(String(localized: "Zurück zu früherer Fassung"))
        let location = min(caret, new.length)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(NSRange(location: range.location, length: 0))
    }

    @objc func compareWithVersion(_ sender: NSMenuItem) {
        guard let version = version(for: sender), let text = VersionHistory.shared.text(of: version) else { return NSSound.beep() }
        let date = DateFormatter.localizedString(from: version.entry.date, dateStyle: .short, timeStyle: .short)
        compareWithText(text, title: String(localized: "\(document.displayName ?? "") (\(date))"))
    }

    @objc func clearVersionHistory(_ sender: Any?) {
        guard let url = document.fileURL, let window = view.window else { return NSSound.beep() }
        let alert = NSAlert()
        alert.messageText = String(localized: "Verlauf von „\(document.displayName ?? "")“ löschen?")
        alert.informativeText = String(localized: "Die früheren Fassungen dieser Datei werden entfernt. Die Datei selbst bleibt, wie sie ist.")
        alert.addButton(withTitle: String(localized: "Löschen"))
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { VersionHistory.shared.clear(for: url) }
        }
    }
}
