import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: SettingsWindowController?

    static func main() {
        Preferences.registerDefaults()
        // The first document controller created becomes the shared one.
        _ = DocumentController()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.mainMenu = MainMenu.build()
        withExtendedLifetime(delegate) { app.run() }
    }

    /// Until launching is done, the app decides itself what to open (see applicationDidFinishLaunching).
    private var isLaunching = true

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        // The app keeps its own session; see Session.swift.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started to open files (Finder, Open With, Dock, `open`): then exactly these files appear,
        // and the stored session is kept as the previous one. NSApplicationLaunchIsDefaultLaunchKey
        // cannot tell, it is false for a plain `open -a` too.
        let controller = NSDocumentController.shared as? DocumentController
        let openedFiles = controller?.openedFilesDuringLaunch == true || !NSDocumentController.shared.documents.isEmpty
        SessionStore.shared.launch(openedFiles: openedFiles)
        isLaunching = false
        controller?.isLaunching = false
        if !openedFiles, NSDocumentController.shared.documents.isEmpty, Preferences.startupActionValue != .nothing {
            NSDocumentController.shared.newDocument(nil)
        }
        SessionStore.shared.save()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !isLaunching }

    func applicationWillTerminate(_ notification: Notification) {
        // Usually written already when the documents were reviewed for quitting.
        SessionStore.shared.save(cleanExit: true)
        FileStateStore.shared.save()
    }

    @objc func showCommandPalette(_ sender: Any?) { CommandPalette.shared.show() }

    @objc func showLanguageFolder(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([LanguageRegistry.userFolder])
    }

    /// Reads all language definitions again and reports the ones that have errors.
    @objc func reloadLanguages(_ sender: Any?) {
        let registry = LanguageRegistry.shared
        registry.reload()
        guard !registry.failures.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Nicht alle Sprachdefinitionen ließen sich lesen.")
        alert.informativeText = registry.failures.joined(separator: "\n\n")
        alert.runModal()
    }

    @objc func previousDocument(_ sender: Any?) { DocumentNavigation.step(by: -1) }
    @objc func nextDocument(_ sender: Any?) { DocumentNavigation.step(by: 1) }

    @objc func restorePreviousSession(_ sender: Any?) {
        SessionStore.shared.restorePrevious()
    }

    @objc func discardPreviousSession(_ sender: Any?) {
        guard let previous = SessionStore.shared.previous else { return }
        if previous.unsavedCount > 0 {
            let alert = NSAlert()
            alert.messageText = String(localized: "Vorige Sitzung verwerfen?")
            alert.informativeText = String(localized: "Sie enthält \(previous.unsavedCount) ungesicherte Texte. Sie gehen dabei verloren.")
            alert.addButton(withTitle: String(localized: "Verwerfen"))
            alert.addButton(withTitle: String(localized: "Abbrechen"))
            alert.buttons[0].hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        SessionStore.shared.discardPrevious()
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        settingsWindow?.showWindow(sender)
    }
}
