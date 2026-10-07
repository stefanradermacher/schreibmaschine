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
import SwiftUI

/// The settings window with one pane per topic, switched in the toolbar.
final class SettingsWindowController: NSWindowController {
    init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.pane(GeneralSettings(), title: String(localized: "Allgemein"), symbol: "gearshape"))
        tabs.addTabViewItem(Self.pane(EditorSettings(), title: String(localized: "Editor"), symbol: "character.cursor.ibeam"))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isRestorable = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func pane(_ view: some View, title: String, symbol: String) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view.frame(width: 460).fixedSize())
        controller.sizingOptions = .preferredContentSize
        // The tab view controller shows the selected pane's title as the window title.
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}

private struct GeneralSettings: View {
    @AppStorage(Preferences.startupAction) private var startupAction = StartupAction.restoreSession.rawValue
    @AppStorage(Preferences.opensDocumentsInTabs) private var opensInTabs = true
    @AppStorage(Preferences.defaultEncoding) private var encoding = Int(String.Encoding.utf8.rawValue)
    @AppStorage(Preferences.writesUTF8BOM) private var writesBOM = false
    @AppStorage(Preferences.defaultLineEnding) private var lineEnding = LineEnding.lf.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Beim Start ohne Datei:", selection: $startupAction) {
                    Text("letzte Sitzung wiederherstellen").tag(StartupAction.restoreSession.rawValue)
                    Text("neues Dokument öffnen").tag(StartupAction.newDocument.rawValue)
                    Text("nichts öffnen").tag(StartupAction.nothing.rawValue)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Startet die Schreibmaschine, weil eine Datei geöffnet wird, erscheint nur diese Datei. Die Sitzung davor lässt sich unter Fenster → Sitzung zurückholen. Ungesicherte Texte bleiben immer erhalten, auch nach einem Absturz.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("Neue Dokumente öffnen:", selection: $opensInTabs) {
                Text("als Tab im vorderen Fenster").tag(true)
                Text("in einem neuen Fenster").tag(false)
            }
            .pickerStyle(.radioGroup)

            Section {
                Picker("Zeichenkodierung:", selection: $encoding) {
                    ForEach(TextEncoding.all, id: \.rawValue) { encoding in
                        Text(TextEncoding.name(of: encoding)).tag(Int(encoding.rawValue))
                    }
                }
                Toggle("UTF-8 mit Byte Order Mark (BOM) sichern", isOn: $writesBOM)
                    .disabled(encoding != Int(String.Encoding.utf8.rawValue))
                Picker("Zeilenenden:", selection: $lineEnding) {
                    ForEach(LineEnding.allCases, id: \.rawValue) { ending in
                        Text(ending.name).tag(ending.rawValue)
                    }
                }
            } header: {
                Text("Für neue Dokumente")
            } footer: {
                Text("Beim Öffnen erkennt die Schreibmaschine Kodierung und Zeilenenden der Datei und behält sie beim Sichern bei. Die Standardkodierung wird außerdem zuerst versucht, wenn eine Datei kein UTF-8 ist.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct EditorSettings: View {
    @AppStorage(Preferences.fontName) private var fontName = ""
    @AppStorage(Preferences.fontSize) private var fontSize = 13.0
    @AppStorage(Preferences.tabWidth) private var tabWidth = 4
    @AppStorage(Preferences.wrapColumn) private var wrapColumn = 80
    @AppStorage(Preferences.indentsWithSpaces) private var indentsWithSpaces = true
    @AppStorage(Preferences.autoIndents) private var autoIndents = true
    @AppStorage(Preferences.highlightsCurrentLine) private var highlightsCurrentLine = true
    @AppStorage(Preferences.highlightsSyntax) private var highlightsSyntax = true
    @AppStorage(Preferences.showsLineNumbers) private var showsLineNumbers = true
    @AppStorage(Preferences.wrapsLines) private var wrapsLines = true
    @AppStorage(Preferences.showsInvisibles) private var showsInvisibles = false

    var body: some View {
        Form {
            LabeledContent {
                HStack {
                    // SF Mono is hidden from the font panel; this is the way back to it.
                    Button("Standard") { fontName = "" }
                        .disabled(fontName.isEmpty)
                    Button("Auswählen …") { FontPicker.shared.show() }
                }
            } label: {
                Text("Schrift")
                Text(fontDescription)
            }

            Section {
                Stepper(value: $tabWidth, in: 1...16) {
                    LabeledContent("Tabbreite:", value: String(localized: "\(tabWidth) Zeichen"))
                }
                Toggle("Mit Leerzeichen statt Tabs einrücken", isOn: $indentsWithSpaces)
                Toggle("Einrückung der vorigen Zeile übernehmen", isOn: $autoIndents)
            } header: {
                Text("Einrückung")
            } footer: {
                Text("Gilt für neue Dokumente und Sprachen ohne eigene Vorgabe. Vorhandene Dateien behalten ihre Einrückung; unter Format → Einrückung lässt sie sich für jedes Dokument ändern.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $wrapColumn, in: 20...200, step: 1) {
                    LabeledContent("Absätze umbrechen bei:", value: String(localized: "\(wrapColumn) Zeichen"))
                }
            } footer: {
                Text("Für Text → Absätze → Umbrechen. Mit „Umbrechen bei Spalte …“ lässt sich jedes Mal eine andere Breite wählen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Zeilennummern", isOn: $showsLineNumbers)
                Toggle("Zeilen umbrechen", isOn: $wrapsLines)
                Toggle("Unsichtbare Zeichen", isOn: $showsInvisibles)
            } header: {
                Text("Für neue Fenster")
            } footer: {
                Text("Im Menü Darstellung lässt sich das für jedes Fenster einzeln umschalten.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Syntax hervorheben", isOn: $highlightsSyntax)
                Toggle("Aktuelle Zeile hervorheben", isOn: $highlightsCurrentLine)
            }
        }
        .formStyle(.grouped)
    }

    private var fontDescription: String {
        let font = Preferences.font
        let name = fontName.isEmpty ? String(localized: "SF Mono (Systemschrift)") : (font.displayName ?? font.fontName)
        return "\(name), \(Int(fontSize)) pt"
    }
}

/// Shows the system font panel and stores the chosen font in the settings.
final class FontPicker: NSObject, NSFontChanging {
    static let shared = FontPicker()

    func show() {
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(Preferences.font, isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    func changeFont(_ sender: NSFontManager?) {
        guard let sender else { return }
        Preferences.setFont(sender.convert(Preferences.font))
    }

    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        [.collection, .face, .size]
    }
}
