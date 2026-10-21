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

/// The menu bar. Standard entries such as the tab and full screen items, Services and help
/// search are added by AppKit.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(textMenu()))
        main.addItem(submenu(formatMenu()))
        let scripts = NSMenu(title: String(localized: "Skripte"))
        scripts.delegate = UserScriptsMenu.shared
        main.addItem(submenu(scripts))
        let window = windowMenu()
        main.addItem(submenu(window))
        let help = helpMenu()
        main.addItem(submenu(help))
        NSApp.windowsMenu = window
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        return item
    }

    private static let appName = "Schreibmaschine"

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: appName)
        menu.addItem(item(String(localized: "Über \(appName)"), #selector(AppDelegate.showAbout(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Einstellungen …"), #selector(AppDelegate.showSettings(_:)), ","))
        menu.addItem(.separator())
        let services = NSMenu(title: String(localized: "Dienste"))
        menu.addItem(submenu(services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "\(appName) ausblenden"), #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item(String(localized: "Andere ausblenden"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item(String(localized: "Alle einblenden"), #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "\(appName) beenden"), #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    /// AppKit adds the search field at the top.
    private static func helpMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Hilfe"))
        menu.addItem(item(String(localized: "\(appName)-Hilfe"), #selector(AppDelegate.openHelp(_:)), "?"))
        menu.addItem(item(String(localized: "\(appName)-Handbuch"), #selector(AppDelegate.openManual(_:))))
        menu.addItem(item(String(localized: "\(appName) im Web"), #selector(AppDelegate.openProductPage(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Fehler melden oder Idee vorschlagen …"), #selector(AppDelegate.sendFeedback(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "\(appName) unterstützen …"), #selector(AppDelegate.showSupport(_:))))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Ablage"))
        menu.addItem(item(String(localized: "Neu"), #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item(String(localized: "Öffnen …"), #selector(NSDocumentController.openDocument(_:)), "o"))
        // "Open Recent" is added by AppKit itself, right after "Open…"; a menu of our own would
        // only appear twice.
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Schließen"), #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item(String(localized: "Sichern"), #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item(String(localized: "Sichern unter …"), #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]))
        menu.addItem(item(String(localized: "Alle sichern"), #selector(NSDocumentController.saveAllDocuments(_:)), "s", [.command, .option]))
        menu.addItem(item(String(localized: "Zurück zur gesicherten Version"), #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(.separator())
        let compare = NSMenu(title: String(localized: "Vergleichen"))
        compare.addItem(item(String(localized: "Mit gesicherter Fassung"), #selector(EditorViewController.compareWithSaved(_:))))
        compare.addItem(item(String(localized: "Mit Zwischenablage"), #selector(EditorViewController.compareWithClipboard(_:))))
        let documents = NSMenu(title: String(localized: "Mit Dokument"))
        documents.delegate = CompareDocumentsMenu.shared
        compare.addItem(submenu(documents))
        compare.addItem(item(String(localized: "Mit Datei …"), #selector(EditorViewController.compareWithFile(_:))))
        compare.addItem(.separator())
        let down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        compare.addItem(item(String(localized: "Nächster Unterschied"), #selector(CompareViewController.nextDifference(_:)), down, [.command, .control]))
        compare.addItem(item(String(localized: "Voriger Unterschied"), #selector(CompareViewController.previousDifference(_:)), up, [.command, .control]))
        compare.addItem(.separator())
        compare.addItem(item(String(localized: "Unterschiede als neues Dokument"), #selector(CompareViewController.openUnifiedDiff(_:))))
        compare.addItem(item(String(localized: "Unterschiede kopieren"), #selector(CompareViewController.copyUnifiedDiff(_:))))
        menu.addItem(submenu(compare))
        menu.addItem(submenu(encodingMenu(
            title: String(localized: "Erneut öffnen mit Kodierung"),
            action: #selector(TextDocument.reinterpretEncoding(_:)))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Papierformat …"), #selector(NSDocument.runPageLayout(_:))))
        menu.addItem(item(String(localized: "Drucken …"), #selector(NSDocument.printDocument(_:)), "p"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Bearbeiten"))
        menu.addItem(item(String(localized: "Widerrufen"), Selector(("undo:")), "z"))
        menu.addItem(item(String(localized: "Wiederholen"), Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Ausschneiden"), #selector(NSText.cut(_:)), "x"))
        menu.addItem(item(String(localized: "Kopieren"), #selector(NSText.copy(_:)), "c"))
        menu.addItem(item(String(localized: "Einsetzen"), #selector(NSText.paste(_:)), "v"))
        menu.addItem(item(String(localized: "Löschen"), #selector(NSText.delete(_:))))
        menu.addItem(item(String(localized: "Alles auswählen"), #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())

        let find = NSMenu(title: String(localized: "Suchen"))
        find.addItem(item(String(localized: "Suchen …"), #selector(EditorViewController.showFindBar(_:)), "f"))
        find.addItem(item(String(localized: "Suchen und ersetzen …"), #selector(EditorViewController.showReplaceBar(_:)), "f", [.command, .option]))
        find.addItem(item(String(localized: "Weitersuchen"), #selector(EditorViewController.findNextMatch(_:)), "g"))
        find.addItem(item(String(localized: "Rückwärts suchen"), #selector(EditorViewController.findPreviousMatch(_:)), "g", [.command, .shift]))
        find.addItem(item(String(localized: "Alle Treffer auswählen"), #selector(EditorViewController.selectAllMatches(_:)), "g", [.command, .control]))
        find.addItem(item(String(localized: "In allen Dokumenten suchen …"), #selector(EditorViewController.showAllDocumentsSearch(_:)), "f", [.command, .shift]))
        find.addItem(.separator())
        find.addItem(item(String(localized: "Auswahl suchen"), #selector(EditorViewController.useSelectionForFind(_:)), "e"))
        find.addItem(item(String(localized: "Auswahl anzeigen"), #selector(NSText.centerSelectionInVisibleArea(_:)), "j"))
        menu.addItem(submenu(find))
        menu.addItem(item(String(localized: "Gehe zu Zeile …"), #selector(EditorViewController.showGoToLine(_:)), "l"))
        let bookmarks = NSMenu(title: String(localized: "Lesezeichen"))
        bookmarks.addItem(item(String(localized: "Lesezeichen setzen"), #selector(EditorPane.toggleBookmark(_:)), "b"))
        bookmarks.addItem(item(String(localized: "Nächstes Lesezeichen"), #selector(EditorPane.nextBookmark(_:)), String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), [.command, .option]))
        bookmarks.addItem(item(String(localized: "Vorheriges Lesezeichen"), #selector(EditorPane.previousBookmark(_:)), String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), [.command, .option]))
        bookmarks.addItem(item(String(localized: "Alle Lesezeichen entfernen"), #selector(EditorPane.removeAllBookmarks(_:))))
        bookmarks.delegate = BookmarksMenu.shared
        menu.addItem(submenu(bookmarks))
        menu.addItem(item(String(localized: "Auswahl erweitern"), #selector(EditorTextView.expandSelection(_:)), String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), [.option]))
        menu.addItem(item(String(localized: "Zur passenden Klammer"), #selector(EditorTextView.jumpToMatchingBracket(_:)), "m", [.command, .shift]))
        menu.addItem(item(String(localized: "Auswahl verkleinern"), #selector(EditorTextView.shrinkSelection(_:)), String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), [.option]))
        menu.addItem(item(String(localized: "Nächstes Vorkommen auswählen"), #selector(EditorTextView.selectNextOccurrence(_:)), "g", [.control]))
        menu.addItem(item(String(localized: "Auswahl in Zeilen teilen"), #selector(EditorTextView.splitSelectionIntoLines(_:)), "l", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Befehlspalette …"), #selector(AppDelegate.showCommandPalette(_:)), "p", [.command, .shift]))

        let spelling = NSMenu(title: String(localized: "Rechtschreibung und Grammatik"))
        spelling.addItem(item(String(localized: "Rechtschreibung und Grammatik einblenden"), #selector(NSText.showGuessPanel(_:)), ":"))
        spelling.addItem(item(String(localized: "Dokument jetzt prüfen"), #selector(NSText.checkSpelling(_:)), ";"))
        spelling.addItem(.separator())
        spelling.addItem(item(String(localized: "Rechtschreibung während der Texteingabe prüfen"), #selector(NSTextView.toggleContinuousSpellChecking(_:))))
        spelling.addItem(item(String(localized: "Grammatik mit Rechtschreibung prüfen"), #selector(NSTextView.toggleGrammarChecking(_:))))
        menu.addItem(submenu(spelling))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Darstellung"))
        menu.addItem(item(String(localized: "Zeilennummern"), #selector(EditorPane.toggleLineNumbers(_:)), "l", [.command, .option]))
        menu.addItem(item(String(localized: "Zeilen umbrechen"), #selector(EditorPane.toggleWrapping(_:)), "w", [.command, .control]))
        menu.addItem(item(String(localized: "Unsichtbare Zeichen"), #selector(EditorPane.toggleInvisibles(_:)), "i", [.command, .option]))
        menu.addItem(item(String(localized: "Dokumentliste"), #selector(AppDelegate.toggleDocumentList(_:)), "s", [.command, .control]))
        menu.addItem(item(String(localized: "Markdown-Vorschau"), #selector(EditorViewController.togglePreview(_:)), "p", [.command, .option]))
        menu.addItem(item(String(localized: "Schreibmaschinen-Modus"), #selector(AppDelegate.toggleTypewriterMode(_:))))
        menu.addItem(item(String(localized: "Fokus-Modus"), #selector(AppDelegate.toggleFocusMode(_:))))
        menu.addItem(item(String(localized: "Ablenkungsfreier Modus"), #selector(EditorViewController.toggleDistractionFree(_:)), "f", [.command, .control, .shift]))
        let folding = NSMenu(title: String(localized: "Code-Faltung"))
        folding.addItem(item(String(localized: "Falten"), #selector(EditorPane.foldBlock(_:)), String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), [.command, .control]))
        folding.addItem(item(String(localized: "Entfalten"), #selector(EditorPane.unfoldBlock(_:)), String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), [.command, .control]))
        folding.addItem(item(String(localized: "Alles falten"), #selector(EditorPane.foldAll(_:)), String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), [.command, .control, .shift]))
        folding.addItem(item(String(localized: "Alles entfalten"), #selector(EditorPane.unfoldAll(_:)), String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), [.command, .control, .shift]))
        menu.addItem(submenu(folding))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Nebeneinander teilen"), #selector(EditorViewController.splitSideBySide(_:)), "t", [.command, .control]))
        menu.addItem(item(String(localized: "Untereinander teilen"), #selector(EditorViewController.splitStacked(_:)), "t", [.command, .control, .option]))
        menu.addItem(item(String(localized: "Teilung aufheben"), #selector(EditorViewController.closeSplit(_:)), "w", [.command, .control, .shift]))
        menu.addItem(item(String(localized: "Zur anderen Hälfte"), #selector(EditorViewController.focusOtherPane(_:)), "j", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Schrift vergrößern"), #selector(EditorViewController.zoomIn(_:)), "+"))
        menu.addItem(item(String(localized: "Schrift verkleinern"), #selector(EditorViewController.zoomOut(_:)), "-"))
        menu.addItem(item(String(localized: "Originalgröße"), #selector(EditorViewController.resetZoom(_:)), "0"))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Vollbildmodus"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    /// Text: the commands of TextCommands, grouped, and running the last one again.
    private static func textMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Text"))
        menu.addItem(item(String(localized: "Kommentar umschalten"), #selector(EditorTextView.toggleComment(_:)), "/"))
        menu.addItem(item(String(localized: "Blockkommentar umschalten"), #selector(EditorTextView.toggleBlockComment(_:)), "/", [.command, .option]))
        menu.addItem(.separator())
        for group in TextCommands.groups {
            let submenu = NSMenu(title: group.title)
            for command in group.commands {
                guard let command else {
                    submenu.addItem(.separator())
                    continue
                }
                let entry = item(command.title, #selector(EditorTextView.performTextCommand(_:)), command.key, command.modifiers)
                entry.representedObject = command.id
                submenu.addItem(entry)
            }
            menu.addItem(self.submenu(submenu))
        }
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Erneut ausführen"), #selector(EditorTextView.repeatTextCommand(_:)), "r"))
        return menu
    }

    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Format"))
        menu.addItem(submenu(encodingMenu(
            title: String(localized: "Zeichenkodierung"),
            action: #selector(TextDocument.changeEncoding(_:)))))
        let lineEndings = NSMenu(title: String(localized: "Zeilenenden"))
        for ending in LineEnding.allCases {
            let entry = item(ending.name, #selector(TextDocument.changeLineEnding(_:)))
            entry.representedObject = ending.rawValue
            lineEndings.addItem(entry)
        }
        menu.addItem(submenu(lineEndings))
        menu.addItem(item(String(localized: "Byte Order Mark (BOM) schreiben"), #selector(TextDocument.toggleBOM(_:))))
        menu.addItem(.separator())
        let languages = NSMenu(title: String(localized: "Sprache"))
        languages.delegate = LanguageMenu.shared
        menu.addItem(submenu(languages))
        let indentation = NSMenu(title: String(localized: "Einrückung"))
        indentation.addItem(item(String(localized: "Mit Leerzeichen"), #selector(TextDocument.indentWithSpaces(_:))))
        indentation.addItem(item(String(localized: "Mit Tabs"), #selector(TextDocument.indentWithTabs(_:))))
        indentation.addItem(.separator())
        for width in [2, 3, 4, 8] {
            indentation.addItem(item(String(localized: "Breite \(width)"), #selector(TextDocument.changeIndentWidth(_:)), tag: width))
        }
        indentation.addItem(.separator())
        indentation.addItem(item(String(localized: "Einrückung der Datei erkennen"), #selector(TextDocument.redetectIndentation(_:))))
        menu.addItem(submenu(indentation))
        return menu
    }

    private static func encodingMenu(title: String, action: Selector) -> NSMenu {
        let menu = NSMenu(title: title)
        for encoding in TextEncoding.menuItems {
            guard let encoding else {
                menu.addItem(.separator())
                continue
            }
            menu.addItem(item(TextEncoding.name(of: encoding), action, tag: Int(encoding.rawValue)))
        }
        menu.addItem(.separator())
        menu.addItem(TextEncoding.moreEncodingsItem { item(TextEncoding.name(of: $0), action, tag: Int($0.rawValue)) })
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Fenster"))
        menu.addItem(item(String(localized: "Im Dock ablegen"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item(String(localized: "Zoomen"), #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        let left = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        let right = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        // Across all windows; ⌃⇥ and ⌃⇧⇥ keep switching the tabs of one window, as everywhere on the Mac.
        menu.addItem(item(String(localized: "Vorheriges Dokument"), #selector(AppDelegate.previousDocument(_:)), left, [.command, .option]))
        menu.addItem(item(String(localized: "Nächstes Dokument"), #selector(AppDelegate.nextDocument(_:)), right, [.command, .option]))
        let documents = NSMenu(title: String(localized: "Dokumente"))
        documents.delegate = DocumentsMenu.shared
        menu.addItem(submenu(documents))
        menu.addItem(.separator())
        let session = NSMenu(title: String(localized: "Sitzung"))
        session.delegate = SessionMenu.shared
        menu.addItem(submenu(session))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Alle nach vorne bringen"), #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}

/// Window → Session: what belongs to the session and comes back at the next start, and the
/// previous session, if one was kept.
final class SessionMenu: NSObject, NSMenuDelegate {
    static let shared = SessionMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let store = SessionStore.shared
        let session = store.capture()

        let header = NSMenuItem(title: Preferences.startupActionValue == .restoreSession
                                ? String(localized: "Kommt beim nächsten Start wieder:")
                                : String(localized: "In der Sitzung (beim Start ohne Datei nicht wiederhergestellt):"),
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if session.isEmpty {
            let empty = NSMenuItem(title: String(localized: "Keine Dokumente"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            empty.indentationLevel = 1
            menu.addItem(empty)
        }
        for (index, window) in session.windows.enumerated() {
            let title = NSMenuItem(title: String(localized: "Fenster \(index + 1)"), action: nil, keyEquivalent: "")
            title.isEnabled = false
            title.indentationLevel = 1
            menu.addItem(title)
            for tab in window.tabs {
                let name = tab.hasBuffer ? String(localized: "\(tab.name) – ungesichert") : tab.name
                let entry = NSMenuItem(title: name, action: #selector(showTab(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = tab.id
                entry.indentationLevel = 2
                entry.toolTip = tab.path
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        let previous = store.previous
        let restore = NSMenuItem(title: String(localized: "Vorige Sitzung wiederherstellen"),
                                 action: previous == nil ? nil : #selector(AppDelegate.restorePreviousSession(_:)), keyEquivalent: "")
        if let previous {
            let documents = previous.windows.reduce(0) { $0 + $1.tabs.count }
            restore.toolTip = previous.unsavedCount > 0
                ? String(localized: "\(documents) Dokumente, davon \(previous.unsavedCount) ungesichert")
                : String(localized: "\(documents) Dokumente")
        }
        menu.addItem(restore)
        menu.addItem(NSMenuItem(title: String(localized: "Vorige Sitzung verwerfen …"),
                                action: previous == nil ? nil : #selector(AppDelegate.discardPreviousSession(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Einstellungen für den Start …"),
                                action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ""))
    }

    @objc private func showTab(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let document = NSDocumentController.shared.documents.first(where: { ($0 as? TextDocument)?.sessionID == id })
        else { return }
        document.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
    }
}


/// Format → Language: plain text, every known language, and the language definitions.
final class LanguageMenu: NSObject, NSMenuDelegate {
    static let shared = LanguageMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let plain = NSMenuItem(title: String(localized: "Reiner Text"), action: #selector(TextDocument.chooseLanguage(_:)), keyEquivalent: "")
        plain.representedObject = ""
        menu.addItem(plain)
        menu.addItem(.separator())
        for language in LanguageRegistry.shared.languages {
            let item = NSMenuItem(title: language.name, action: #selector(TextDocument.chooseLanguage(_:)), keyEquivalent: "")
            item.representedObject = language.id
            if !language.isBuiltIn { item.toolTip = String(localized: "Eigene Sprachdefinition") }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Definition dieser Sprache bearbeiten"),
                                action: #selector(TextDocument.editLanguageDefinition(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: String(localized: "Ordner mit eigenen Sprachen zeigen"),
                                action: #selector(AppDelegate.showLanguageFolder(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: String(localized: "Sprachdefinitionen neu laden"),
                                action: #selector(AppDelegate.reloadLanguages(_:)), keyEquivalent: ""))
    }
}

/// The bookmarks of the front document, listed below the commands with the text of their line.
final class BookmarksMenu: NSObject, NSMenuDelegate {
    static let shared = BookmarksMenu()
    private let marker = "bookmark"

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.representedObject as? String == marker { menu.removeItem(item) }
        guard let document = NSDocumentController.shared.currentDocument as? TextDocument, !document.bookmarks.isEmpty else { return }
        let separator = NSMenuItem.separator()
        separator.representedObject = marker
        menu.addItem(separator)
        let text = document.textStorage.string as NSString
        for line in document.bookmarkedLines {
            var range = text.lineRange(for: NSRange(location: document.lineIndex.start(ofLine: line), length: 0))
            range.length = min(range.length, 200)
            let content = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(localized: "Zeile \(line)") + (content.isEmpty ? "" : ": " + String(content.prefix(60)))
            let item = NSMenuItem(title: title, action: #selector(EditorPane.goToBookmark(_:)), keyEquivalent: "")
            item.tag = line
            item.representedObject = marker
            menu.addItem(item)
        }
    }
}

/// Ablage → Vergleichen → Mit Dokument: the other open documents.
final class CompareDocumentsMenu: NSObject, NSMenuDelegate {
    static let shared = CompareDocumentsMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = NSDocumentController.shared.currentDocument
        let others = NSDocumentController.shared.documents.compactMap { $0 as? TextDocument }.filter { $0 !== current }
        if others.isEmpty {
            let empty = NSMenuItem(title: String(localized: "Keine anderen Dokumente"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for document in others {
            let item = NSMenuItem(title: document.displayName, action: #selector(EditorViewController.compareWithDocument(_:)), keyEquivalent: "")
            item.representedObject = document
            menu.addItem(item)
        }
    }
}
