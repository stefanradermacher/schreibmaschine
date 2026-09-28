import Foundation

/// How a document was shown: selection, scroll position and the switches of the View menu.
struct ViewState: Codable, Equatable {
    var selectionLocation = 0
    var selectionLength = 0
    /// UTF-16 offset of the first line visible at the top.
    var topOffset = 0
    var wrapsLines: Bool
    var showsLineNumbers: Bool
    var showsInvisibles: Bool
    var zoom: Double = 0
    /// Lines with a bookmark; they belong to the document, not the view, but are kept with it.
    var bookmarks: [Int]?
    /// Lines heading a folded block; like bookmarks, they belong to the document.
    var folds: [Int]?
    /// The second half of a split view; the fields above describe the first.
    var split: SplitState?
}

struct SplitState: Codable, Equatable {
    /// Side by side; otherwise one above the other.
    var sideBySide: Bool
    var second: EditorPane.State
    /// Share of the first half, from 0 to 1.
    var fraction: Double
}

/// What the app remembers about a file between openings: how it was shown, and the encoding
/// if it was chosen by hand with Reopen with Encoding.
///
/// Stored as JSON in Application Support, keyed by path. The file itself stays untouched.
final class FileStateStore {
    static let shared = FileStateStore()

    struct Entry: Codable {
        var view: ViewState?
        var encoding: UInt?
        /// Chosen by hand; otherwise the language is recognized again at every opening.
        var language: String?
        /// Chosen by hand; otherwise recognized from the text.
        var indentation: Indentation?
        var lastUsed: Date
    }

    /// The most recently used files are kept, the others forgotten.
    private let limit = 1000
    private var entries: [String: Entry] = [:]
    private var saveScheduled = false
    private let url: URL

    private init() {
        url = SessionStore.supportDirectory.appendingPathComponent("FileStates.json")
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    private func key(_ fileURL: URL) -> String { fileURL.standardizedFileURL.path }

    func viewState(for fileURL: URL) -> ViewState? { entries[key(fileURL)]?.view }
    func encoding(for fileURL: URL) -> String.Encoding? { entries[key(fileURL)]?.encoding.map(String.Encoding.init) }

    func language(for fileURL: URL) -> String? { entries[key(fileURL)]?.language }
    func indentation(for fileURL: URL) -> Indentation? { entries[key(fileURL)]?.indentation }

    /// Remembers a language chosen by hand; "" stands for plain text.
    func recordLanguage(_ id: String, for fileURL: URL) {
        update(fileURL) { $0.language = id }
    }

    func recordIndentation(_ indentation: Indentation?, for fileURL: URL) {
        update(fileURL) { $0.indentation = indentation }
    }

    func record(_ view: ViewState, for fileURL: URL) {
        update(fileURL) { $0.view = view }
    }

    /// Remembers an encoding chosen by hand; nil forgets it, so the next opening recognizes it again.
    func recordEncoding(_ encoding: String.Encoding?, for fileURL: URL) {
        update(fileURL) { $0.encoding = encoding?.rawValue }
    }

    private func update(_ fileURL: URL, _ change: (inout Entry) -> Void) {
        var entry = entries[key(fileURL)] ?? Entry(lastUsed: Date())
        change(&entry)
        entry.lastUsed = Date()
        entries[key(fileURL)] = entry
        scheduleSave()
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in save() }
    }

    func save() {
        saveScheduled = false
        if entries.count > limit {
            let keep = entries.sorted { $0.value.lastUsed > $1.value.lastUsed }.prefix(limit)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
