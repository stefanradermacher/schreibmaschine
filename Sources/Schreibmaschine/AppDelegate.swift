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

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        settingsWindow?.showWindow(sender)
    }
}
