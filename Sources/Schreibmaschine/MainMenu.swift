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
        main.addItem(submenu(formatMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        let help = NSMenu(title: String(localized: "Hilfe"))
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
        menu.addItem(item(String(localized: "Über \(appName)"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
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

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Ablage"))
        menu.addItem(item(String(localized: "Neu"), #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item(String(localized: "Öffnen …"), #selector(NSDocumentController.openDocument(_:)), "o"))
        // AppKit fills the menu that contains "Clear Menu".
        let recent = NSMenu(title: String(localized: "Benutzte Dokumente"))
        recent.addItem(item(String(localized: "Einträge löschen"), #selector(NSDocumentController.clearRecentDocuments(_:))))
        menu.addItem(submenu(recent))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Schließen"), #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item(String(localized: "Sichern"), #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item(String(localized: "Sichern unter …"), #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]))
        menu.addItem(item(String(localized: "Alle sichern"), #selector(NSDocumentController.saveAllDocuments(_:)), "s", [.command, .option]))
        menu.addItem(item(String(localized: "Zurück zur gesicherten Version"), #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(.separator())
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
        menu.addItem(item(String(localized: "Zeilennummern"), #selector(EditorViewController.toggleLineNumbers(_:)), "l", [.command, .option]))
        menu.addItem(item(String(localized: "Zeilen umbrechen"), #selector(EditorViewController.toggleWrapping(_:)), "w", [.command, .control]))
        menu.addItem(item(String(localized: "Unsichtbare Zeichen"), #selector(EditorViewController.toggleInvisibles(_:)), "i", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Schrift vergrößern"), #selector(EditorViewController.zoomIn(_:)), "+"))
        menu.addItem(item(String(localized: "Schrift verkleinern"), #selector(EditorViewController.zoomOut(_:)), "-"))
        menu.addItem(item(String(localized: "Originalgröße"), #selector(EditorViewController.resetZoom(_:)), "0"))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Vollbildmodus"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
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
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Fenster"))
        menu.addItem(item(String(localized: "Im Dock ablegen"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item(String(localized: "Zoomen"), #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        let left = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        let right = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
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
