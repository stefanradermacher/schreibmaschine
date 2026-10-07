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
import UniformTypeIdentifiers

/// A text file. The text lives in a TextKit 2 content storage that every view of the document
/// shares, with LF as the only line break; encoding, byte order mark and line ending are
/// properties of the document and are applied when saving.
final class TextDocument: NSDocument {
    let contentStorage = NSTextContentStorage()
    let lineIndex: LineIndex
    let highlighter: SyntaxHighlighter

    /// The language for coloring, comments and indentation; nil is plain text.
    private(set) var language: LanguageDefinition?
    /// The language was chosen by hand and is not recognized again, for example after "Save As".
    private var languageChosenByUser = false
    private(set) var indentation = Indentation.preferred

    private(set) var encoding: String.Encoding = Preferences.defaultEncodingValue
    private(set) var hasBOM = false
    private(set) var lineEnding: LineEnding = Preferences.defaultLineEndingValue
    /// The file had more than one kind of line ending; saving unifies them.
    private(set) var hadMixedLineEndings = false

    /// Posted when encoding, byte order mark or line ending change.
    static let formatDidChange = Notification.Name("TextDocumentFormatDidChange")
    /// Posted when the text was read again from the file.
    static let textDidReload = Notification.Name("TextDocumentTextDidReload")
    /// Posted when the language changes; the views color the text anew.
    static let languageDidChange = Notification.Name("TextDocumentLanguageDidChange")
    /// Posted after an edit: the coloring from the line in userInfo["line"] on is out of date.
    static let coloringDidInvalidate = Notification.Name("TextDocumentColoringDidInvalidate")
    /// Posted when the indentation changes.
    static let indentationDidChange = Notification.Name("TextDocumentIndentationDidChange")
    /// Posted when folds are made or opened.
    static let foldsDidChange = Notification.Name("TextDocumentFoldsDidChange")
    /// Hidden text of folded blocks, sorted (Folding.swift).
    var folds: [NSRange] = []
    /// Posted when bookmarks are set or removed.
    static let bookmarksDidChange = Notification.Name("TextDocumentBookmarksDidChange")

    var textStorage: NSTextStorage { contentStorage.textStorage! }

    /// Identifies the document in the session; its unsaved text is stored under this name.
    var sessionID = UUID()
    /// The name of a file that is gone, for the text kept from it; saving asks for a new place.
    var keptName: String? {
        didSet { displayName = keptName }
    }

    override var fileURL: URL? {
        didSet {
            // Once saved, the document is named after its file again.
            if fileURL != nil, keptName != nil { keptName = nil }
            // Saved under a new name, a text gets the language that name suggests.
            if fileURL != oldValue, fileURL != nil, !languageChosenByUser {
                setLanguage(detectedLanguage(), byUser: false)
            }
            DocumentListView.setNeedsUpdate()
        }
    }
    private var observers: [NSObjectProtocol] = []

    override init() {
        let storage = contentStorage.textStorage!
        lineIndex = LineIndex(storage: storage)
        highlighter = SyntaxHighlighter(storage: storage, lineIndex: lineIndex)
        super.init()
        contentStorage.delegate = self
        hasBOM = encoding == .utf8 ? UserDefaults.standard.bool(forKey: Preferences.writesUTF8BOM) : false
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: textStorage, queue: nil) { [weak self] _ in
                self?.textDidEdit()
            },
            center.addObserver(forName: LanguageRegistry.didChange, object: nil, queue: .main) { [weak self] _ in
                self?.languagesDidReload()
            },
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// While the text is replaced by loading or restoring, edits are not the user's.
    private var isReplacingText = false

    private func textDidEdit() {
        SessionStore.shared.setNeedsSave()
        if textStorage.editedMask.contains(.editedCharacters) {
            // The edited line may now end in a different state; the lines after it start anew.
            let line = lineIndex.lineNumber(at: textStorage.editedRange.location)
            highlighter.invalidate(fromLine: line)
            NotificationCenter.default.post(name: Self.coloringDidInvalidate, object: self, userInfo: ["line": line])
            adjustBookmarks()
            adjustFolds()
        }
        guard textStorage.editedMask.contains(.editedCharacters), !isReplacingText,
              undoManager?.isUndoing != true, undoManager?.isRedoing != true
        else { return }
        // Typing marks the document as changed through its undo registration, once the event is
        // done. Text inserted through accessibility (dictation, Keyboard Viewer, automation) is
        // not registered for undo; without this it would count as unchanged and not be kept.
        // The check waits until the undo group of a keystroke is surely closed.
        // A save in between would make the text unchanged again; then this edit is in the file.
        let generation = saveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !isDocumentEdited, saveGeneration == generation else { return }
            updateChangeCount(.changeDone)
        }
    }

    // MARK: - Bookmarks

    /// The starts of the lines with a bookmark, sorted. They follow their lines through edits.
    private(set) var bookmarks: [Int] = []

    var bookmarkedLines: [Int] { bookmarks.map { lineIndex.lineNumber(at: $0) } }

    func setBookmarkedLines(_ lines: [Int]) {
        bookmarks = Set(lines.filter { $0 >= 1 && $0 <= lineIndex.lineCount }).sorted().map { lineIndex.start(ofLine: $0) }
        NotificationCenter.default.post(name: Self.bookmarksDidChange, object: self)
    }

    func toggleBookmark(atLine line: Int) {
        var lines = bookmarkedLines
        if let index = lines.firstIndex(of: line) { lines.remove(at: index) } else { lines.append(line) }
        setBookmarkedLines(lines)
        SessionStore.shared.setNeedsSave()
    }

    /// Moves the bookmarks with the text. A bookmark in deleted text goes to the line where the
    /// deletion was; one at the start of a line moves down when a line break is typed there.
    private func adjustBookmarks() {
        guard !bookmarks.isEmpty else { return }
        let edited = textStorage.editedRange
        let delta = textStorage.changeInLength
        let oldEnd = edited.upperBound - delta
        let text = textStorage.string as NSString
        let insertedLineBreak = edited.length > 0 && text.substring(with: edited).contains("\n")
        let moved = bookmarks.map { start -> Int in
            if start < edited.location { return start }
            if start == edited.location && oldEnd == edited.location { return insertedLineBreak ? start + delta : start }
            if start >= oldEnd { return start + delta }
            return edited.location
        }
        let adjusted = Array(Set(moved.map { text.lineRange(for: NSRange(location: min($0, text.length), length: 0)).location })).sorted()
        if adjusted != bookmarks {
            bookmarks = adjusted
            NotificationCenter.default.post(name: Self.bookmarksDidChange, object: self)
        }
    }

    var editor: EditorViewController? {
        (windowControllers.first as? DocumentWindowController)?.editor
    }

    /// The text has to be kept by the session: it has changes that are not in a file.
    var needsBuffer: Bool {
        isDocumentEdited || (fileURL == nil && textStorage.length > 0)
    }

    // MARK: - NSDocument

    // Saving writes the file only on ⌘S. Unsaved changes are kept by the session instead, so
    // quitting never asks and never loses text.
    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController())
    }

    override func read(from url: URL, ofType typeName: String) throws {
        let data = try Data(contentsOf: url)
        // An encoding chosen by hand for this file before is used again, as long as it fits.
        if let chosen = FileStateStore.shared.encoding(for: url), (try? load(data, as: chosen)) != nil {
            setUpLanguageAndIndentation(for: url)
            return
        }
        try load(data, as: nil)
        setUpLanguageAndIndentation(for: url)
    }

    // MARK: - Language and indentation

    /// The language chosen for the file before, or the one its name and first line suggest;
    /// the indentation chosen before, or the one the text uses, or the language's.
    private func setUpLanguageAndIndentation(for url: URL) {
        let store = FileStateStore.shared
        if let id = store.language(for: url) {
            languageChosenByUser = true
            setLanguage(LanguageRegistry.shared.language(id: id), byUser: false)
        } else {
            setLanguage(detectedLanguage(name: url.lastPathComponent), byUser: false)
        }
        if let chosen = store.indentation(for: url) {
            setIndentation(chosen, byUser: false)
        } else {
            detectIndentation(byUser: false)
        }
    }

    private func detectedLanguage(name: String? = nil) -> LanguageDefinition? {
        let text = textStorage.string as NSString
        let firstLine = text.substring(with: text.lineRange(for: NSRange(location: 0, length: 0)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LanguageRegistry.shared.detect(fileName: name ?? fileURL?.lastPathComponent, firstLine: firstLine)
    }

    func setLanguage(_ language: LanguageDefinition?, byUser: Bool) {
        if byUser {
            languageChosenByUser = true
            if let fileURL { FileStateStore.shared.recordLanguage(language?.id ?? "", for: fileURL) }
        }
        let changed = language?.id != self.language?.id
        self.language = language
        highlighter.setLanguage(language)
        if changed || byUser {
            NotificationCenter.default.post(name: Self.languageDidChange, object: self)
        }
    }

    func setIndentation(_ indentation: Indentation, byUser: Bool) {
        if byUser, let fileURL { FileStateStore.shared.recordIndentation(indentation, for: fileURL) }
        guard indentation != self.indentation else { return }
        self.indentation = indentation
        NotificationCenter.default.post(name: Self.indentationDidChange, object: self)
    }

    /// The indentation the text uses; for a text without any, the language's or the settings'.
    func detectIndentation(byUser: Bool) {
        let fallback = language?.indentation ?? .preferred
        let detected = Indentation.detect(in: textStorage.string, fallbackWidth: fallback.width) ?? fallback
        if byUser, let fileURL { FileStateStore.shared.recordIndentation(nil, for: fileURL) }
        setIndentation(detected, byUser: false)
    }

    /// Definitions were reloaded: the same language again, as now defined.
    private func languagesDidReload() {
        guard let id = language?.id else { return }
        setLanguage(LanguageRegistry.shared.language(id: id), byUser: false)
        NotificationCenter.default.post(name: Self.languageDidChange, object: self)
    }

    /// Saving a language definition from the folder of the user's own ones makes it take effect.
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping ((any Error)?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            completionHandler(error)
            guard error == nil,
                  url.deletingLastPathComponent().standardizedFileURL == LanguageRegistry.userFolder.standardizedFileURL
            else { return }
            let registry = LanguageRegistry.shared
            registry.reload()
            if let failure = registry.failures.first(where: { $0.hasPrefix(url.lastPathComponent) }) {
                let alert = NSAlert()
                alert.messageText = String(localized: "Die Sprachdefinition enthält einen Fehler.")
                alert.informativeText = failure
                if let window = self.windowForSheet { alert.beginSheetModal(for: window) } else { alert.runModal() }
            }
        }
    }

    override func read(from data: Data, ofType typeName: String) throws {
        try load(data, as: nil)
    }

    /// Counts saves and reverts, so a late check after an edit can tell whether one happened.
    private var saveGeneration = 0

    // Saving reports through the token variant, not updateChangeCount(_:).
    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        saveGeneration += 1
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        SessionStore.shared.setNeedsSave()
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        if change == .changeCleared || change == .changeAutosaved { saveGeneration += 1 }
        super.updateChangeCount(change)
        SessionStore.shared.setNeedsSave()
        DocumentListView.setNeedsUpdate()
    }

    override func close() {
        if let fileURL, let view = editor?.viewState {
            FileStateStore.shared.record(view, for: fileURL)
        }
        super.close()
        stopSecurityScope()
        SessionStore.shared.setNeedsSave()
    }

    // MARK: - Session

    private var scopedURL: URL?
    private var cachedBookmark: (url: URL, data: Data)?

    /// Security-scoped bookmark of the file, so the session may open it again after a restart.
    var bookmark: Data? {
        guard let fileURL else { return nil }
        if let cachedBookmark, cachedBookmark.url == fileURL { return cachedBookmark.data }
        guard let data = try? fileURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return nil
        }
        cachedBookmark = (fileURL, data)
        return data
    }

    /// Keeps access to a file opened through a bookmark for as long as the document is open.
    func adoptSecurityScope(of url: URL, accessing: Bool) {
        if accessing { scopedURL = url }
    }

    private func stopSecurityScope() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    /// Puts back a text kept by the session, with the format it had; the document counts as
    /// changed, since the text is not in a file.
    func restore(text: String, encoding: String.Encoding, hasBOM: Bool, lineEnding: LineEnding) {
        self.encoding = encoding
        self.hasBOM = hasBOM
        self.lineEnding = lineEnding
        isReplacingText = true
        defer { isReplacingText = false }
        undoManager?.disableUndoRegistration()
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: text)
        textStorage.setAttributes(EditorStyle.attributes(), range: NSRange(location: 0, length: textStorage.length))
        textStorage.endEditing()
        undoManager?.enableUndoRegistration()
        updateChangeCount(.changeDone)
        NotificationCenter.default.post(name: Self.formatDidChange, object: self)
    }

    override func data(ofType typeName: String) throws -> Data {
        var text = textStorage.string
        if lineEnding != .lf {
            text = text.replacingOccurrences(of: "\n", with: lineEnding.separator)
        }
        guard let body = text.data(using: encoding, allowLossyConversion: false) else {
            throw DocumentError.notEncodable(encoding: encoding, characters: unencodableCharacters(in: text))
        }
        var data = Data(hasBOM ? TextEncoding.bom(for: encoding) : [])
        data.append(body)
        return data
    }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        let plainText = UTType.plainText.identifier
        guard let fileType, fileType != plainText else { return [plainText] }
        return [fileType, plainText]
    }

    override class func isNativeType(_ type: String) -> Bool { true }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        if let fileURL, !fileURL.pathExtension.isEmpty { return fileURL.pathExtension }
        return UTType(typeName)?.preferredFilenameExtension ?? "txt"
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        // Any name and extension goes; the text is the same whatever the file is called.
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        savePanel.canSelectHiddenExtension = false
        return true
    }

    override var shouldRunSavePanelWithAccessoryView: Bool { false }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.string = textStorage.string
        view.font = Preferences.font
        view.textColor = .black
        view.backgroundColor = .white
        view.sizeToFit()
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = displayName
        return operation
    }

    // MARK: - Loading

    private func load(_ data: Data, as requested: String.Encoding?) throws {
        let decoded: TextEncoding.Decoded
        do {
            decoded = try TextEncoding.decode(data, as: requested, preferred: Preferences.defaultEncodingValue)
        } catch TextEncoding.DecodingError.binary {
            throw DocumentError.binary
        } catch {
            throw DocumentError.notDecodable(encoding: requested)
        }
        let (ending, isMixed) = LineEnding.detect(in: decoded.text)
        encoding = decoded.encoding
        hasBOM = decoded.hasBOM
        lineEnding = ending ?? Preferences.defaultLineEndingValue
        hadMixedLineEndings = isMixed

        let text = decoded.text.normalizingLineEndings
        isReplacingText = true
        defer { isReplacingText = false }
        undoManager?.disableUndoRegistration()
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: text)
        textStorage.setAttributes(EditorStyle.attributes(), range: NSRange(location: 0, length: textStorage.length))
        textStorage.endEditing()
        undoManager?.enableUndoRegistration()
        undoManager?.removeAllActions()
        NotificationCenter.default.post(name: Self.formatDidChange, object: self)
        NotificationCenter.default.post(name: Self.textDidReload, object: self)
    }

    /// Reads the file again in another encoding.
    func reinterpret(as encoding: String.Encoding) {
        guard let fileURL else { return }
        let apply = { [self] in
            do {
                let data = try Data(contentsOf: fileURL)
                try load(data, as: encoding)
                updateChangeCount(.changeCleared)
                FileStateStore.shared.recordEncoding(encoding, for: fileURL)
            } catch {
                presentError(error)
            }
        }
        guard isDocumentEdited, let window = windowForSheet else { return apply() }
        let alert = NSAlert()
        alert.messageText = String(localized: "Ungesicherte Änderungen verwerfen?")
        alert.informativeText = String(localized: "Die Datei wird in der neuen Kodierung neu gelesen. Änderungen seit dem letzten Sichern gehen dabei verloren.")
        alert.addButton(withTitle: String(localized: "Neu lesen"))
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { apply() }
        }
    }

    // MARK: - Format

    /// Changes the encoding used for saving. If the text contains characters the encoding
    /// cannot represent, asks first; saving then fails until the characters are gone.
    func changeEncoding(to newEncoding: String.Encoding) {
        guard newEncoding != encoding else { return }
        let apply = { [self] in
            // UTF-8 goes without a byte order mark unless the settings say otherwise;
            // UTF-16 is hardly readable without one.
            let bom = newEncoding == .utf8
                ? UserDefaults.standard.bool(forKey: Preferences.writesUTF8BOM)
                : TextEncoding.supportsBOM(newEncoding)
            setFormat(encoding: newEncoding, hasBOM: bom, lineEnding: lineEnding)
        }
        let characters = unencodableCharacters(in: textStorage.string, encoding: newEncoding)
        guard !characters.isEmpty, let window = windowForSheet else { return apply() }
        let alert = NSAlert()
        alert.messageText = String(localized: "Nicht alle Zeichen lassen sich in „\(TextEncoding.name(of: newEncoding))“ darstellen.")
        alert.informativeText = String(localized: "Betroffen sind: \(characters). Solange sie im Text stehen, lässt sich das Dokument in dieser Kodierung nicht sichern.")
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        alert.addButton(withTitle: String(localized: "Trotzdem umstellen"))
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn { apply() }
        }
    }

    func setBOM(_ enabled: Bool) {
        guard TextEncoding.supportsBOM(encoding) else { return }
        setFormat(encoding: encoding, hasBOM: enabled, lineEnding: lineEnding)
    }

    func changeLineEnding(to newEnding: LineEnding) {
        guard newEnding != lineEnding || hadMixedLineEndings else { return }
        setFormat(encoding: encoding, hasBOM: hasBOM, lineEnding: newEnding)
    }

    /// Sets the format undoably; undoing restores the previous one.
    private func setFormat(encoding newEncoding: String.Encoding, hasBOM newBOM: Bool, lineEnding newEnding: LineEnding) {
        let old = (encoding, hasBOM, lineEnding)
        undoManager?.registerUndo(withTarget: self) { document in
            document.setFormat(encoding: old.0, hasBOM: old.1, lineEnding: old.2)
        }
        undoManager?.setActionName(String(localized: "Format ändern"))
        encoding = newEncoding
        hasBOM = newBOM
        lineEnding = newEnding
        hadMixedLineEndings = false
        NotificationCenter.default.post(name: Self.formatDidChange, object: self)
    }

    private func unencodableCharacters(in text: String, encoding: String.Encoding? = nil) -> String {
        let encoding = encoding ?? self.encoding
        guard !text.canBeConverted(to: encoding) else { return "" }
        var found: [Character] = []
        for character in text where !found.contains(character) && !String(character).canBeConverted(to: encoding) {
            found.append(character)
            if found.count == 10 { break }
        }
        return found.map { "„\($0)“" }.joined(separator: ", ")
    }

    // MARK: - Menu actions

    @objc func changeEncoding(_ sender: NSMenuItem) {
        changeEncoding(to: String.Encoding(rawValue: UInt(sender.tag)))
    }

    @objc func reinterpretEncoding(_ sender: NSMenuItem) {
        reinterpret(as: String.Encoding(rawValue: UInt(sender.tag)))
    }

    @objc func toggleBOM(_ sender: Any?) {
        setBOM(!hasBOM)
    }

    @objc func changeLineEnding(_ sender: NSMenuItem) {
        if let ending = sender.representedObject as? String, let lineEnding = LineEnding(rawValue: ending) {
            changeLineEnding(to: lineEnding)
        }
    }

    @objc func chooseLanguage(_ sender: NSMenuItem) {
        let id = sender.representedObject as? String ?? ""
        setLanguage(LanguageRegistry.shared.language(id: id), byUser: true)
    }

    @objc func indentWithSpaces(_ sender: Any?) {
        setIndentation(Indentation(width: indentation.width, usesSpaces: true), byUser: true)
    }

    @objc func indentWithTabs(_ sender: Any?) {
        setIndentation(Indentation(width: indentation.width, usesSpaces: false), byUser: true)
    }

    @objc func changeIndentWidth(_ sender: NSMenuItem) {
        setIndentation(Indentation(width: sender.tag, usesSpaces: indentation.usesSpaces), byUser: true)
    }

    @objc func redetectIndentation(_ sender: Any?) {
        detectIndentation(byUser: true)
    }

    /// Opens the definition of the document's language for editing, as a copy in the folder of
    /// the user's own definitions if it is a built-in one.
    @objc func editLanguageDefinition(_ sender: Any?) {
        guard let language else { return }
        do {
            let url = language.isBuiltIn ? try LanguageRegistry.shared.editableCopy(of: language) : language.url
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        } catch {
            presentError(error)
        }
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(chooseLanguage(_:)):
            item.state = (item.representedObject as? String ?? "") == (language?.id ?? "") ? .on : .off
            return true
        case #selector(indentWithSpaces(_:)):
            item.state = indentation.usesSpaces ? .on : .off
            return true
        case #selector(indentWithTabs(_:)):
            item.state = indentation.usesSpaces ? .off : .on
            return true
        case #selector(changeIndentWidth(_:)):
            item.state = item.tag == indentation.width ? .on : .off
            return true
        case #selector(editLanguageDefinition(_:)):
            return language != nil
        case #selector(changeEncoding(_:)):
            item.state = UInt(item.tag) == encoding.rawValue ? .on : .off
            return true
        case #selector(reinterpretEncoding(_:)):
            return fileURL != nil
        case #selector(toggleBOM(_:)):
            item.state = hasBOM ? .on : .off
            return TextEncoding.supportsBOM(encoding)
        case #selector(changeLineEnding(_:)):
            item.state = (item.representedObject as? String) == lineEnding.rawValue ? .on : .off
            return true
        default:
            return super.validateMenuItem(item)
        }
    }
}

enum DocumentError: LocalizedError {
    case binary
    case notDecodable(encoding: String.Encoding?)
    case notEncodable(encoding: String.Encoding, characters: String)

    var errorDescription: String? {
        switch self {
        case .binary:
            String(localized: "Die Datei scheint keinen Text zu enthalten.")
        case .notDecodable(let encoding?):
            String(localized: "Die Datei lässt sich nicht als „\(TextEncoding.name(of: encoding))“ lesen.")
        case .notDecodable(nil):
            String(localized: "Die Kodierung der Datei ließ sich nicht erkennen.")
        case .notEncodable(let encoding, _):
            String(localized: "Der Text lässt sich nicht als „\(TextEncoding.name(of: encoding))“ sichern.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .binary:
            String(localized: "Sie scheint keinen Text zu enthalten: Sie enthält Nullbytes, wie sie in Programmen, Bildern oder Archiven vorkommen.")
        case .notDecodable:
            String(localized: "Wähle eine andere Kodierung unter Ablage → Erneut öffnen mit Kodierung.")
        case .notEncodable(_, let characters):
            String(localized: "Diese Zeichen gibt es in der Kodierung nicht: \(characters). Wähle unter Format → Zeichenkodierung zum Beispiel UTF-8.")
        }
    }
}
