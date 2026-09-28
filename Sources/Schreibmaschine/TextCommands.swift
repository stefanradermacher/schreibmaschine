import AppKit

/// A command of the Text menu.
struct TextCommand {
    /// A value the command asks for before running, such as a separator; the answer is kept
    /// for next time and used again by "Run Again".
    struct Parameter {
        let prompt: String
        let defaultValue: String
        var hint: String? = nil
    }

    let id: String
    let title: String
    var key = ""
    var modifiers: NSEvent.ModifierFlags = [.command]
    var parameter: Parameter?
    let run: (EditorTextView, String) throws -> Void
}

/// The commands of the Text menu and the way they reach the text: on the selection, and without
/// one on what makes sense — the whole document for sorting, the current line for moving it,
/// the word at the insertion point for changing case, the paragraph for wrapping.
enum TextCommands {
    struct Group {
        let title: String
        let commands: [TextCommand?]   // nil is a separator
    }

    private static let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    private static let down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
    private static let backspace = String(Character(UnicodeScalar(NSBackspaceCharacter)!))
    private static let escapeHint = String(localized: "\\t steht für einen Tab, \\n für einen Zeilenumbruch.")

    static let groups: [Group] = [
        Group(title: String(localized: "Zeilen"), commands: [
            TextCommand(id: "duplicate", title: String(localized: "Duplizieren"), key: "d") { view, _ in view.duplicateLines() },
            TextCommand(id: "deleteLines", title: String(localized: "Zeilen löschen"), key: backspace) { view, _ in view.deleteLines() },
            TextCommand(id: "moveUp", title: String(localized: "Nach oben verschieben"), key: up, modifiers: [.option, .shift]) { view, _ in view.moveLines(up: true) },
            TextCommand(id: "moveDown", title: String(localized: "Nach unten verschieben"), key: down, modifiers: [.option, .shift]) { view, _ in view.moveLines(up: false) },
            nil,
            TextCommand(id: "join", title: String(localized: "Zeilen verbinden"), key: "j", modifiers: [.control, .shift]) { view, _ in
                view.transformLines(scope: .selectionOrNextLine) { [TextTransforms.join($0, separator: " ")] }
            },
            TextCommand(id: "joinWith", title: String(localized: "Zeilen verbinden mit …"),
                        parameter: .init(prompt: String(localized: "Zeilen verbinden mit:"), defaultValue: ", ", hint: escapeHint)) { view, separator in
                view.transformLines(scope: .selectionOrDocument) { [TextTransforms.join($0, separator: separator)] }
            },
            TextCommand(id: "split", title: String(localized: "Zeilen teilen an …"),
                        parameter: .init(prompt: String(localized: "Zeilen teilen an:"), defaultValue: ",", hint: escapeHint)) { view, separator in
                view.transformLines(scope: .selectionOrLine) { TextTransforms.split($0, at: separator) }
            },
            nil,
            TextCommand(id: "sortAscending", title: String(localized: "Sortieren (A–Z)")) { view, _ in
                view.transformLines(scope: .selectionOrDocument) { TextTransforms.sort($0, .ascending) }
            },
            TextCommand(id: "sortDescending", title: String(localized: "Sortieren (Z–A)")) { view, _ in
                view.transformLines(scope: .selectionOrDocument) { TextTransforms.sort($0, .descending) }
            },
            TextCommand(id: "sortNumeric", title: String(localized: "Nach Zahlen sortieren")) { view, _ in
                view.transformLines(scope: .selectionOrDocument) { TextTransforms.sort($0, .numeric) }
            },
            TextCommand(id: "unique", title: String(localized: "Dubletten entfernen")) { view, _ in
                view.transformLines(scope: .selectionOrDocument, TextTransforms.removeDuplicates)
            },
            TextCommand(id: "reverse", title: String(localized: "Reihenfolge umkehren")) { view, _ in
                view.transformLines(scope: .selectionOrDocument) { $0.reversed() }
            },
            TextCommand(id: "shuffle", title: String(localized: "Mischen")) { view, _ in
                view.transformLines(scope: .selectionOrDocument) { $0.shuffled() }
            },
            TextCommand(id: "number", title: String(localized: "Nummerieren")) { view, _ in
                view.transformLines(scope: .selectionOrDocument, TextTransforms.number)
            },
            TextCommand(id: "removeEmpty", title: String(localized: "Leere Zeilen entfernen")) { view, _ in
                view.transformLines(scope: .selectionOrDocument, TextTransforms.removeEmpty)
            },
        ]),
        Group(title: String(localized: "Absätze"), commands: [
            TextCommand(id: "wrap", title: String(localized: "Umbrechen")) { view, _ in
                view.transformLines(scope: .selectionOrParagraph) {
                    TextTransforms.wrap($0, column: Preferences.wrapColumnValue, tabWidth: Preferences.tabWidthValue)
                }
            },
            TextCommand(id: "wrapAt", title: String(localized: "Umbrechen bei Spalte …"),
                        parameter: .init(prompt: String(localized: "Umbrechen bei Spalte:"), defaultValue: "72")) { view, value in
                guard let column = Int(value.trimmingCharacters(in: .whitespaces)), column > 0 else {
                    throw TextTransforms.Failure.notDecodable(String(localized: "Bitte eine Spaltenzahl angeben, zum Beispiel 72."))
                }
                view.transformLines(scope: .selectionOrParagraph) {
                    TextTransforms.wrap($0, column: column, tabWidth: Preferences.tabWidthValue)
                }
            },
            TextCommand(id: "unwrap", title: String(localized: "Umbrüche entfernen")) { view, _ in
                view.transformLines(scope: .selectionOrParagraph, TextTransforms.unwrap)
            },
            nil,
            TextCommand(id: "indent", title: String(localized: "Einrücken"), key: "]") { view, _ in view.indentLines() },
            TextCommand(id: "outdent", title: String(localized: "Ausrücken"), key: "[") { view, _ in view.outdentLines() },
            nil,
            TextCommand(id: "quote", title: String(localized: "Als Zitat markieren")) { view, _ in
                view.transformLines(scope: .selectionOrParagraph, TextTransforms.quote)
            },
            TextCommand(id: "unquote", title: String(localized: "Zitatzeichen entfernen")) { view, _ in
                view.transformLines(scope: .selectionOrParagraph, TextTransforms.unquote)
            },
        ]),
        Group(title: String(localized: "Leerraum"), commands: [
            TextCommand(id: "trimTrailing", title: String(localized: "Leerzeichen am Zeilenende entfernen")) { view, _ in
                view.transformLines(scope: .selectionOrDocument, TextTransforms.trimTrailing)
            },
            TextCommand(id: "tabsToSpaces", title: String(localized: "Tabs in Leerzeichen umwandeln")) { view, _ in
                view.transformLines(scope: .selectionOrDocument) { TextTransforms.tabsToSpaces($0, tabWidth: Preferences.tabWidthValue) }
            },
            TextCommand(id: "spacesToTabs", title: String(localized: "Einrückung in Tabs umwandeln")) { view, _ in
                view.transformLines(scope: .selectionOrDocument) { TextTransforms.spacesToTabs($0, tabWidth: Preferences.tabWidthValue) }
            },
            TextCommand(id: "collapseSpaces", title: String(localized: "Mehrfache Leerzeichen zusammenfassen")) { view, _ in
                view.transformLines(scope: .selectionOrDocument, TextTransforms.collapseSpaces)
            },
        ]),
        Group(title: String(localized: "Schreibweise"), commands: [
            caseCommand("upper", String(localized: "GROSSBUCHSTABEN"), .upper),
            caseCommand("lower", String(localized: "kleinbuchstaben"), .lower),
            caseCommand("sentence", String(localized: "Satzanfang groß"), .sentence),
            caseCommand("title", String(localized: "Wörter Groß"), .title),
            nil,
            caseCommand("camel", "camelCase", .camel),
            caseCommand("snake", "snake_case", .snake),
            caseCommand("kebab", "kebab-case", .kebab),
        ]),
        Group(title: String(localized: "Spalten"), commands: [
            TextCommand(id: "align", title: String(localized: "An Zeichen ausrichten …"),
                        parameter: .init(prompt: String(localized: "Ausrichten am ersten:"), defaultValue: "=")) { view, separator in
                view.transformLines(scope: .selectionOrParagraph) { TextTransforms.align($0, at: separator, tabWidth: Preferences.tabWidthValue) }
            },
            TextCommand(id: "table", title: String(localized: "Markdown-Tabelle formatieren")) { view, _ in
                view.transformLines(scope: .selectionOrTable, TextTransforms.formatMarkdownTable)
            },
        ]),
        Group(title: String(localized: "Kodieren"), commands: [
            textCommand("urlEncode", String(localized: "URL-kodieren"), TextTransforms.urlEncode),
            throwingCommand("urlDecode", String(localized: "URL-Kodierung auflösen"), TextTransforms.urlDecode),
            nil,
            textCommand("base64Encode", String(localized: "Base64-kodieren"), TextTransforms.base64Encode),
            throwingCommand("base64Decode", String(localized: "Base64 dekodieren"), TextTransforms.base64Decode),
            nil,
            textCommand("htmlEncode", String(localized: "HTML-Zeichen maskieren"), TextTransforms.htmlEncode),
            textCommand("htmlDecode", String(localized: "HTML-Entitäten auflösen"), TextTransforms.htmlDecode),
            nil,
            TextCommand(id: "jsonFormat", title: String(localized: "JSON formatieren")) { view, _ in
                let indent = Preferences.indentsWithSpacesValue ? String(repeating: " ", count: Preferences.tabWidthValue) : "\t"
                try view.transformText(scope: .selectionOrDocument) { try TextTransforms.formatJSON($0, indent: indent) }
            },
            throwingCommand("jsonMinify", String(localized: "JSON verkleinern"), TextTransforms.minifyJSON),
        ]),
    ]

    private static func caseCommand(_ id: String, _ title: String, _ style: TextTransforms.Case) -> TextCommand {
        TextCommand(id: id, title: title) { view, _ in
            try view.transformText(scope: .selectionOrWord) { TextTransforms.changeCase($0, to: style) }
        }
    }

    private static func textCommand(_ id: String, _ title: String, _ transform: @escaping (String) -> String) -> TextCommand {
        TextCommand(id: id, title: title) { view, _ in
            try view.transformText(scope: .selectionOrDocument, transform)
        }
    }

    private static func throwingCommand(_ id: String, _ title: String, _ transform: @escaping (String) throws -> String) -> TextCommand {
        TextCommand(id: id, title: title) { view, _ in
            try view.transformText(scope: .selectionOrDocument, transform)
        }
    }

    static func command(_ id: String) -> TextCommand? {
        for group in groups {
            if let command = group.commands.compactMap({ $0 }).first(where: { $0.id == id }) { return command }
        }
        return nil
    }

    /// The last command run from the Text menu, with its value, for "Run Again".
    static var last: (command: TextCommand, value: String)?

    static func storedValue(for command: TextCommand) -> String {
        UserDefaults.standard.string(forKey: "TextCommandValue." + command.id) ?? command.parameter?.defaultValue ?? ""
    }

    static func store(_ value: String, for command: TextCommand) {
        UserDefaults.standard.set(value, forKey: "TextCommandValue." + command.id)
    }
}

// MARK: - Running commands

extension EditorTextView {
    @objc func performTextCommand(_ sender: Any?) {
        guard let id = (sender as? NSMenuItem)?.representedObject as? String, let command = TextCommands.command(id) else { return }
        guard let parameter = command.parameter else { return run(command, value: "") }
        askValue(for: command, parameter: parameter) { [weak self] value in
            self?.run(command, value: value)
        }
    }

    @objc func repeatTextCommand(_ sender: Any?) {
        guard let last = TextCommands.last else { return NSSound.beep() }
        run(last.command, value: last.value)
    }

    private func run(_ command: TextCommand, value: String) {
        currentCommandTitle = command.title
        defer { currentCommandTitle = nil }
        do {
            try command.run(self, SearchQuery.expandEscapes(value).replacingOccurrences(of: "\\\\", with: "\\"))
            TextCommands.last = (command, value)
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "„\(command.title)“ war nicht möglich.")
            alert.informativeText = error.localizedDescription
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
    }

    /// Asks for the value of a command in a sheet; the field holds the answer from last time.
    private func askValue(for command: TextCommand, parameter: TextCommand.Parameter, then run: @escaping (String) -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = parameter.prompt
        alert.informativeText = parameter.hint ?? ""
        let field = NSTextField(string: TextCommands.storedValue(for: command))
        field.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Ausführen"))
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            TextCommands.store(field.stringValue, for: command)
            run(field.stringValue)
        }
    }
}

// MARK: - What a command works on

extension EditorTextView {
    enum Scope {
        /// Selected lines; without a selection the whole document.
        case selectionOrDocument
        /// Selected lines; without a selection the current line.
        case selectionOrLine
        /// Selected lines; without a selection the current line and the next one.
        case selectionOrNextLine
        /// Selected lines; without a selection the paragraph around the insertion point.
        case selectionOrParagraph
        /// Selected lines; without a selection the Markdown table around the insertion point.
        case selectionOrTable
        /// The selected text; without a selection the word at the insertion point.
        case selectionOrWord
    }

    private var text: NSString { string as NSString }

    /// Whole lines covering the selection. A selection ending at the start of a line does not
    /// take that line along.
    func lineRange(of selection: NSRange) -> NSRange {
        var end = selection.upperBound
        if selection.length > 0, end > selection.location, text.character(at: end - 1) == 0x0A { end -= 1 }
        return text.lineRange(for: NSRange(location: selection.location, length: end - selection.location))
    }

    private func range(for scope: Scope) -> NSRange {
        let selection = selectedRange()
        switch scope {
        case .selectionOrWord:
            if selection.length > 0 { return selection }
            return wordRange(at: selection.location)
        case _ where selection.length > 0:
            return lineRange(of: selection)
        case .selectionOrDocument:
            return NSRange(location: 0, length: text.length)
        case .selectionOrLine:
            return text.lineRange(for: selection)
        case .selectionOrNextLine:
            let line = text.lineRange(for: selection)
            guard line.upperBound < text.length else { return line }
            return text.lineRange(for: NSRange(location: line.location, length: line.length + 1))
        case .selectionOrParagraph:
            // A line break counts as white space: an empty line ends the paragraph.
            return block(around: selection.location) { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case .selectionOrTable:
            return block(around: selection.location) { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
        default:
            return selection
        }
    }

    /// The lines around a location for which `belongs` holds, such as the lines of a paragraph.
    private func block(around location: Int, where belongs: (String) -> Bool) -> NSRange {
        let current = text.lineRange(for: NSRange(location: location, length: 0))
        guard belongs(text.substring(with: current)) else { return current }
        var start = current.location
        while start > 0 {
            let previous = text.lineRange(for: NSRange(location: start - 1, length: 0))
            guard belongs(text.substring(with: previous)) else { break }
            start = previous.location
        }
        var end = current.upperBound
        while end < text.length {
            let next = text.lineRange(for: NSRange(location: end, length: 0))
            guard belongs(text.substring(with: next)) else { break }
            end = next.upperBound
        }
        return NSRange(location: start, length: end - start)
    }

    /// The word at a location: letters, digits and underscores, as in names in code.
    func wordRange(at location: Int) -> NSRange {
        let isWord = { (unit: unichar) -> Bool in
            guard let scalar = Unicode.Scalar(unit) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || unit == 0x5F
        }
        var start = location, end = location
        while start > 0, isWord(text.character(at: start - 1)) { start -= 1 }
        while end < text.length, isWord(text.character(at: end)) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Replaces the lines of the scope by the transformed lines and selects them. A final line
    /// break stays where it was.
    func transformLines(scope: Scope, _ transform: ([String]) -> [String]) {
        let range = range(for: scope)
        var block = text.substring(with: range)
        let endsWithNewline = block.hasSuffix("\n")
        if endsWithNewline { block.removeLast() }
        var result = transform(block.components(separatedBy: "\n")).joined(separator: "\n")
        if endsWithNewline { result += "\n" }
        replace(range, with: result)
    }

    /// Replaces the text of the scope by the transformed text and selects it. White space and
    /// line breaks around it stay as they are, so a selected line keeps its line break.
    func transformText(scope: Scope, _ transform: (String) throws -> String) throws {
        var range = range(for: scope)
        while range.length > 0, CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(text.character(at: range.location)) ?? " ") {
            range.location += 1
            range.length -= 1
        }
        while range.length > 0, CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(text.character(at: range.upperBound - 1)) ?? " ") {
            range.length -= 1
        }
        guard range.length > 0 else { return NSSound.beep() }
        try replace(range, with: transform(text.substring(with: range)))
    }

    /// One undoable change, named after the running command; afterwards the new text is selected.
    func replace(_ range: NSRange, with replacement: String, select selection: NSRange? = nil) {
        guard replacement != text.substring(with: range) else { return }
        guard shouldChangeText(in: range, replacementString: replacement) else { return NSSound.beep() }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        if let title = currentCommandTitle { undoManager?.setActionName(title.replacingOccurrences(of: " …", with: "")) }
        var newSelection = selection ?? NSRange(location: range.location, length: (replacement as NSString).length)
        // Selecting a block without its final line break reads better.
        if selection == nil, replacement.hasSuffix("\n"), newSelection.length > 0 { newSelection.length -= 1 }
        setSelectedRange(newSelection)
        scrollRangeToVisible(NSRange(location: newSelection.location, length: 0))
    }
}

// MARK: - Line commands

extension EditorTextView {
    /// ⌘D: a selection within a line is doubled in place, otherwise the lines are copied below.
    func duplicateLines() {
        let selection = selectedRange()
        if selection.length > 0 && !text.substring(with: selection).contains("\n") {
            let copy = text.substring(with: selection)
            replace(NSRange(location: selection.upperBound, length: 0), with: copy,
                    select: NSRange(location: selection.upperBound, length: selection.length))
            return
        }
        let lines = lineRange(of: selection)
        var block = text.substring(with: lines)
        let insertion: String
        let location: Int
        if block.hasSuffix("\n") {
            insertion = block
            location = lines.upperBound
        } else {
            // The last line without a line break: the copy goes behind a new one.
            block = "\n" + block
            insertion = block
            location = lines.upperBound
        }
        let offset = (insertion as NSString).length
        replace(NSRange(location: location, length: 0), with: insertion,
                select: NSRange(location: selection.location + offset, length: selection.length))
    }

    /// ⌘⌫: deletes the lines of the selection, or the current line.
    func deleteLines() {
        var lines = lineRange(of: selectedRange())
        // The last line has no line break of its own; the one before it goes instead.
        if lines.upperBound == text.length, lines.location > 0, !text.substring(with: lines).hasSuffix("\n") {
            lines = NSRange(location: lines.location - 1, length: lines.length + 1)
        }
        let caret = min(lines.location, text.length - lines.length)
        replace(lines, with: "", select: NSRange(location: max(caret, 0), length: 0))
    }

    /// ⌥⇧↑ and ⌥⇧↓: moves the lines of the selection past the line above or below.
    func moveLines(up: Bool) {
        let selection = selectedRange()
        var lines = lineRange(of: selection)
        var block = text.substring(with: lines)
        if up {
            guard lines.location > 0 else { return NSSound.beep() }
            let previous = text.lineRange(for: NSRange(location: lines.location - 1, length: 0))
            var above = text.substring(with: previous)
            if !block.hasSuffix("\n") { block += "\n"; above.removeLast() }
            let range = NSRange(location: previous.location, length: previous.length + lines.length)
            replace(range, with: block + above,
                    select: NSRange(location: selection.location - previous.length, length: selection.length))
        } else {
            guard lines.upperBound < text.length else { return NSSound.beep() }
            let next = text.lineRange(for: NSRange(location: lines.upperBound, length: 0))
            var below = text.substring(with: next)
            if !below.hasSuffix("\n") { below += "\n"; block.removeLast() }
            lines.length += next.length
            replace(lines, with: below + block,
                    select: NSRange(location: selection.location + (below as NSString).length, length: selection.length))
        }
    }

    private var indentUnit: String {
        Preferences.indentsWithSpacesValue ? String(repeating: " ", count: Preferences.tabWidthValue) : "\t"
    }

    func indentLines() {
        transformLines(scope: .selectionOrLine) { TextTransforms.indent($0, unit: indentUnit) }
    }

    func outdentLines() {
        transformLines(scope: .selectionOrLine) { TextTransforms.outdent($0, width: Preferences.tabWidthValue) }
    }
}
