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

/// A script of the user's from the folder macOS keeps for the app's scripts
/// (~/Library/Application Scripts/<bundle id>/). It may be written in any language that runs on
/// the Mac; it gets text on its standard input and gives text back on its standard output.
///
/// Two lines near the top, in whatever comment syntax, say what goes in and what happens with
/// the result:
///
///     # @input selection          selection (the document if nothing is selected), document, none
///     # @output replace-selection replace-selection, replace-document, insert, new-document, copy, none
///
/// Without them a script is a filter: the selection, or the document if nothing is selected,
/// goes in and is replaced by what comes out. The path of the file, if it has one, is the first
/// argument. The script runs outside the sandbox, as the user's own program.
struct UserScript {
    enum Input: String {
        case selection, document, none
    }

    enum Output: String {
        case replaceSelection = "replace-selection", replaceDocument = "replace-document", insert
        case newDocument = "new-document", copy, none
    }

    let url: URL
    var input = Input.selection
    var output = Output.replaceSelection

    /// The name in the menu: the file name without extension and without a leading number,
    /// which only orders the scripts ("01 Sort.sh" is "Sort").
    var name: String { Self.displayName(of: url) }

    init(url: URL) {
        self.url = url
        // The header is near the top; a large script is not read as a whole.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 4096)) ?? Data(), as: UTF8.self)
        for line in head.split(separator: "\n").prefix(30) {
            if let value = Self.value(of: "@input", in: line), let input = Input(rawValue: value) { self.input = input }
            if let value = Self.value(of: "@output", in: line), let output = Output(rawValue: value) { self.output = output }
        }
    }

    private static func value(of key: String, in line: Substring) -> String? {
        guard let range = line.range(of: key) else { return nil }
        let rest = line[range.upperBound...].drop { $0 == " " || $0 == ":" || $0 == "=" || $0 == "\t" }
        let value = rest.prefix { $0.isLetter || $0 == "-" }
        return value.isEmpty ? nil : value.lowercased()
    }

    static func displayName(of url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let digits = base.prefix { $0.isNumber }
        guard !digits.isEmpty else { return base }
        let rest = base.dropFirst(digits.count).drop { $0 == " " || $0 == "-" || $0 == "_" || $0 == "." }
        return rest.isEmpty ? base : String(rest)
    }

    // MARK: - The folder

    /// The folder for the scripts; macOS creates it with the app's container. The app may read
    /// it but not write to it, except where the user allows it in an open panel.
    static var folder: URL? {
        try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    /// The entries of a folder in the order of their names, as the Finder sorts them; hidden
    /// files are left out.
    static func contents(of folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - Running

    struct Failure: Error {
        let message: String
    }

    /// Runs the script with the input on its standard input; calls back on the main thread with
    /// its standard output, or what went wrong.
    func run(input: String?, arguments: [String], completion: @escaping (Result<String, Failure>) -> Void) {
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            return completion(.failure(Failure(message: String(localized: "Die Datei ist nicht ausführbar. Im Terminal macht „chmod +x“ sie dazu."))))
        }
        let task: NSUserUnixTask
        do {
            task = try NSUserUnixTask(url: url)
        } catch {
            return completion(.failure(Failure(message: error.localizedDescription)))
        }
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        task.standardInput = inPipe.fileHandleForReading
        task.standardOutput = outPipe.fileHandleForWriting
        task.standardError = errPipe.fileHandleForWriting
        // A script that does not read its input closes the pipe; that must not end the app.
        _ = fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        // Output is read while the script runs, so a long one does not fill the pipe and wait.
        let group = DispatchGroup()
        var output = Data(), errors = Data()
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            output = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        }
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            errors = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
        }

        task.execute(withArguments: arguments) { error in
            // The script has ended; with these ends closed, the reading above comes to an end.
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()
            try? inPipe.fileHandleForReading.close()
            group.notify(queue: .main) {
                let errorText = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if let error {
                    let message = errorText.isEmpty ? error.localizedDescription : errorText
                    completion(.failure(Failure(message: String(message.prefix(2000)))))
                } else {
                    completion(.success(String(decoding: output, as: UTF8.self)))
                }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            if let input { try? inPipe.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
            try? inPipe.fileHandleForWriting.close()
        }
    }

    // MARK: - Examples

    /// Small scripts that show the three ways of working, in the language of the app.
    static var examples: [(name: String, text: String)] {
        let german = Locale.preferredLanguages.first?.hasPrefix("de") ?? true
        if german {
            return [
                ("01 Datum einfügen.sh", """
                #!/bin/zsh
                # Fügt das heutige Datum an der Einfügemarke ein.
                # @input none
                # @output insert
                print -n -- "$(date '+%d.%m.%Y')"

                """),
                ("02 Zeilen nach Länge sortieren.sh", """
                #!/bin/zsh
                # Sortiert die ausgewählten Zeilen, ohne Auswahl alle, von der kürzesten zur längsten.
                # Ohne @input und @output ersetzt das Ergebnis, was hineinging.
                awk '{ print length($0) "\\t" $0 }' | sort -n -s -k1,1 | cut -f2-

                """),
                ("03 Gliederung als neues Dokument.sh", """
                #!/bin/zsh
                # Die Überschriften eines Markdown-Dokuments als eingerückte Liste in einem neuen Dokument.
                # @input document
                # @output new-document
                grep -E '^#{1,6} ' | awk '{ match($0, /^#+/); printf "%*s- %s\\n", (RLENGTH - 1) * 2, "", substr($0, RLENGTH + 2) }'

                """),
            ]
        }
        return [
            ("01 Insert Date.sh", """
            #!/bin/zsh
            # Inserts today's date at the insertion point.
            # @input none
            # @output insert
            print -n -- "$(date '+%Y-%m-%d')"

            """),
            ("02 Sort Lines by Length.sh", """
            #!/bin/zsh
            # Sorts the selected lines, or all of them, from the shortest to the longest.
            # Without @input and @output the result replaces what went in.
            awk '{ print length($0) "\\t" $0 }' | sort -n -s -k1,1 | cut -f2-

            """),
            ("03 Outline as New Document.sh", """
            #!/bin/zsh
            # The headings of a Markdown document as an indented list in a new document.
            # @input document
            # @output new-document
            grep -E '^#{1,6} ' | awk '{ match($0, /^#+/); printf "%*s- %s\\n", (RLENGTH - 1) * 2, "", substr($0, RLENGTH + 2) }'

            """),
        ]
    }
}

/// The Scripts menu: read anew each time it opens, so new scripts appear without a restart.
/// Folders become submenus.
final class UserScriptsMenu: NSObject, NSMenuDelegate {
    static let shared = UserScriptsMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let folder = UserScript.folder {
            add(folder, to: menu, depth: 0)
        }
        if menu.items.isEmpty {
            let empty = NSMenuItem(title: String(localized: "Keine Skripte"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Skriptordner öffnen"), action: #selector(openFolder(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: String(localized: "Beispielskripte installieren …"), action: #selector(installExamples(_:)), keyEquivalent: ""))
        for item in menu.items.suffix(2) { item.target = self }
    }

    private func add(_ folder: URL, to menu: NSMenu, depth: Int) {
        for url in UserScript.contents(of: folder) {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isFolder {
                guard depth < 3 else { continue }
                let submenu = NSMenu(title: UserScript.displayName(of: url))
                add(url, to: submenu, depth: depth + 1)
                guard !submenu.items.isEmpty else { continue }
                let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
                item.submenu = submenu
                menu.addItem(item)
            } else {
                let item = NSMenuItem(title: UserScript.displayName(of: url), action: #selector(EditorViewController.runUserScript(_:)), keyEquivalent: "")
                item.representedObject = url
                menu.addItem(item)
            }
        }
    }

    @objc func openFolder(_ sender: Any?) {
        guard let folder = UserScript.folder else { return NSSound.beep() }
        NSWorkspace.shared.open(folder)
    }

    /// The app may write to the scripts folder only where the user allows it, by choosing the
    /// folder in an open panel.
    @objc func installExamples(_ sender: Any?) {
        guard let folder = UserScript.folder else { return NSSound.beep() }
        let panel = NSOpenPanel()
        panel.directoryURL = folder
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = String(localized: "Installieren")
        panel.message = String(localized: "Die Beispielskripte kommen in den Skriptordner. Bestätige ihn mit „Installieren“.")
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        guard chosen.standardizedFileURL.path == folder.standardizedFileURL.path else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Das ist nicht der Skriptordner.")
            alert.informativeText = String(localized: "Skripte findet die Schreibmaschine nur in \(folder.path).")
            alert.runModal()
            return
        }
        var failed: [String] = []
        for (name, text) in UserScript.examples {
            let url = chosen.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            } catch {
                failed.append(name)
            }
        }
        if !failed.isEmpty {
            let alert = NSAlert()
            alert.messageText = String(localized: "Nicht alle Beispielskripte ließen sich anlegen.")
            alert.informativeText = failed.joined(separator: "\n")
            alert.runModal()
        }
    }
}

extension EditorViewController {
    /// Runs a script from the Scripts menu on this document.
    @objc func runUserScript(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let script = UserScript(url: url)
        let text = document.textStorage.string as NSString
        let whole = NSRange(location: 0, length: text.length)
        let selection = textView.selectedRange()
        let source: NSRange? = switch script.input {
        case .selection: selection.length > 0 ? selection : whole
        case .document: whole
        case .none: nil
        }
        let target: NSRange = switch script.output {
        case .replaceDocument: whole
        case .insert: NSRange(location: (source ?? selection).upperBound, length: 0)
        default: source ?? selection
        }
        let input = source.map { text.substring(with: $0) }

        // An edit while the script runs makes the place for its result uncertain.
        final class Flag { var isSet = false }
        let edited = Flag()
        let observer = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification,
                                                              object: document.textStorage, queue: nil) { _ in edited.isSet = true }
        let arguments = [document.fileURL?.path].compactMap { $0 }
        script.run(input: input, arguments: arguments) { [weak self] result in
            NotificationCenter.default.removeObserver(observer)
            guard let self else { return }
            switch result {
            case .failure(let failure):
                showScriptAlert(String(localized: "Das Skript „\(script.name)“ ist fehlgeschlagen."), failure.message)
            case .success(var output):
                // Most programs end their output with a line break; it belongs there only if the
                // input had one.
                if output.hasSuffix("\n"), !(input ?? "").hasSuffix("\n") { output.removeLast() }
                apply(output, of: script, at: target, textChanged: edited.isSet)
            }
        }
    }

    private func apply(_ output: String, of script: UserScript, at target: NSRange, textChanged: Bool) {
        switch script.output {
        case .replaceSelection, .replaceDocument, .insert:
            guard !textChanged else {
                let alert = NSAlert()
                alert.messageText = String(localized: "Der Text hat sich geändert, während „\(script.name)“ lief.")
                alert.informativeText = String(localized: "Das Ergebnis wurde deshalb nicht eingesetzt.")
                alert.addButton(withTitle: String(localized: "In neuem Dokument öffnen"))
                alert.addButton(withTitle: String(localized: "Verwerfen"))
                guard let window = view.window else { return }
                alert.beginSheetModal(for: window) { response in
                    if response == .alertFirstButtonReturn { Self.openDocument(with: output) }
                }
                return
            }
            let textView = textView
            textView.currentCommandTitle = script.name
            let length = (output as NSString).length
            textView.replace(target, with: output,
                             select: script.output == .insert ? NSRange(location: target.location + length, length: 0) : nil)
            textView.currentCommandTitle = nil
        case .newDocument:
            Self.openDocument(with: output)
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)
        case .none:
            break
        }
    }

    private static func openDocument(with text: String) {
        guard let document = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? TextDocument else { return }
        document.restore(text: text.normalizingLineEndings, encoding: .utf8, hasBOM: false, lineEnding: .lf)
    }

    private func showScriptAlert(_ message: String, _ information: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = information
        if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
