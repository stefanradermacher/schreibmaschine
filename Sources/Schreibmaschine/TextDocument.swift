import AppKit
import UniformTypeIdentifiers

/// A text file. The text lives in a TextKit 2 content storage that every view of the document
/// shares, with LF as the only line break; encoding, byte order mark and line ending are
/// properties of the document and are applied when saving.
final class TextDocument: NSDocument {
    let contentStorage = NSTextContentStorage()
    let lineIndex: LineIndex

    private(set) var encoding: String.Encoding = Preferences.defaultEncodingValue
    private(set) var hasBOM = false
    private(set) var lineEnding: LineEnding = Preferences.defaultLineEndingValue
    /// The file had more than one kind of line ending; saving unifies them.
    private(set) var hadMixedLineEndings = false

    /// Posted when encoding, byte order mark or line ending change.
    static let formatDidChange = Notification.Name("TextDocumentFormatDidChange")
    /// Posted when the text was read again from the file.
    static let textDidReload = Notification.Name("TextDocumentTextDidReload")

    var textStorage: NSTextStorage { contentStorage.textStorage! }

    /// Identifies the document in the session; its unsaved text is stored under this name.
    var sessionID = UUID()
    /// The name of a file that is gone, for the text kept from it; saving asks for a new place.
    var keptName: String? {
        didSet { displayName = keptName }
    }

    override var fileURL: URL? {
        // Once saved, the document is named after its file again.
        didSet { if fileURL != nil, keptName != nil { keptName = nil } }
    }
    private var editObserver: NSObjectProtocol?

    override init() {
        lineIndex = LineIndex(storage: contentStorage.textStorage!)
        super.init()
        hasBOM = encoding == .utf8 ? UserDefaults.standard.bool(forKey: Preferences.writesUTF8BOM) : false
        editObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: textStorage, queue: nil
        ) { [weak self] _ in
            self?.textDidEdit()
        }
    }

    deinit {
        if let editObserver { NotificationCenter.default.removeObserver(editObserver) }
    }

    /// While the text is replaced by loading or restoring, edits are not the user's.
    private var isReplacingText = false

    private func textDidEdit() {
        SessionStore.shared.setNeedsSave()
        guard textStorage.editedMask.contains(.editedCharacters), !isReplacingText,
              undoManager?.isUndoing != true, undoManager?.isRedoing != true
        else { return }
        // Typing marks the document as changed through its undo registration, once the event is
        // done. Text inserted through accessibility (dictation, Keyboard Viewer, automation) is
        // not registered for undo; without this it would count as unchanged and not be kept.
        // The check waits until the undo group of a keystroke is surely closed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !isDocumentEdited else { return }
            updateChangeCount(.changeDone)
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
        if let chosen = FileStateStore.shared.encoding(for: url), (try? load(data, as: chosen)) != nil { return }
        try load(data, as: nil)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        try load(data, as: nil)
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        SessionStore.shared.setNeedsSave()
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

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
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
