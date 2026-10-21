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
import UniformTypeIdentifiers

/// The kinds of text the Schreibmaschine offers to open by default. HTML, CSV and logs can be
/// chosen one by one but are left out of "all": web pages are usually opened in the browser,
/// tables in a spreadsheet and logs in Console.
enum TextFormat: String, CaseIterable, Identifiable {
    case plainText, markdown, json, yaml, toml, xml, html, css, javascript, swift, python, php, shell, sql, lua, log, csv, diff

    var id: Self { self }

    var title: String {
        switch self {
        case .plainText: String(localized: "Reiner Text")
        case .markdown: "Markdown"
        case .json: "JSON"
        case .yaml: "YAML"
        case .toml: "TOML / INI"
        case .xml: "XML"
        case .html: "HTML"
        case .css: "CSS"
        case .javascript: "JavaScript"
        case .swift: "Swift"
        case .python: "Python"
        case .php: "PHP"
        case .shell: String(localized: "Shell-Skripte")
        case .sql: "SQL"
        case .lua: "Lua"
        case .log: String(localized: "Protokolle")
        case .csv: "CSV / TSV"
        case .diff: "Diff / Patch"
        }
    }

    var types: [UTType] {
        let identifiers: [String] = switch self {
        case .plainText: ["public.plain-text"]
        case .markdown: ["net.daringfireball.markdown"]
        case .json: ["public.json"]
        case .yaml: ["public.yaml"]
        case .toml: ["public.toml", "com.microsoft.ini"]
        case .xml: ["public.xml"]
        case .html: ["public.html"]
        case .css: ["public.css"]
        case .javascript: ["com.netscape.javascript-source"]
        case .swift: ["public.swift-source"]
        case .python: ["public.python-script"]
        case .php: ["public.php-script"]
        case .shell: ["public.shell-script", "public.zsh-script", "public.bash-script"]
        case .sql: ["org.iso.sql"]
        case .lua: ["org.lua.lua-source"]
        case .log: ["com.apple.log"]
        case .csv: ["public.comma-separated-values-text", "public.tab-separated-values-text"]
        case .diff: ["public.patch-file"]
        }
        return identifiers.compactMap { UTType($0) }
    }

    /// Whether "all formats" and the offer include it.
    var isInAll: Bool { self != .html && self != .csv && self != .log }

    /// The formats whose types the system knows. The app declares the ones macOS does not, but a
    /// format without any type must never count as the Schreibmaschine's.
    static var available: [TextFormat] { allCases.filter { !$0.types.isEmpty } }

    static var all: [TextFormat] { available.filter(\.isInAll) }

    /// The app that opens this format now; for several types, the one for the first.
    var currentApplication: URL? {
        types.first.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    }

    var isSchreibmaschineDefault: Bool {
        !types.isEmpty && types.allSatisfy { type in
            NSWorkspace.shared.urlForApplication(toOpen: type).map(DefaultAppOffer.isSchreibmaschine) ?? false
        }
    }
}

/// Offers to make the Schreibmaschine the default app for text and code – rarely and only once
/// it is really in use:
/// - never before it was used on three different days,
/// - at most twice, the second time 30 days and three more days of use after the first,
/// - never again once it was the default (switching back was a deliberate choice),
/// - only when it is installed in an Applications folder.
@MainActor
enum DefaultAppOffer {
    static let requiredUsageDays = 3
    static let repeatAfter: TimeInterval = 30 * 24 * 60 * 60
    static let maxOffers = 2

    private enum Key {
        static let usageDays = "defaultApp.usageDays"
        static let lastUsageDay = "defaultApp.lastUsageDay"
        static let offerCount = "defaultApp.offerCount"
        static let lastOfferDate = "defaultApp.lastOfferDate"
        static let usageDaysAtLastOffer = "defaultApp.usageDaysAtLastOffer"
        static let wasDefault = "defaultApp.wasDefault"
        /// The app each type had before, as type identifier → app path, to go back to it.
        static let previousApps = "defaultApp.previousApps"
    }

    private static var defaults: UserDefaults { .standard }
    /// Only one window per app session shows the offer.
    private static var offeredThisSession = false

    // MARK: State of the system

    static var isDefaultForAll: Bool { TextFormat.all.allSatisfy(\.isSchreibmaschineDefault) }

    static var isDefaultForAny: Bool { TextFormat.available.contains(where: \.isSchreibmaschineDefault) }

    /// Plain text is the format that matters most; the offer goes by it.
    static var isDefault: Bool { TextFormat.plainText.isSchreibmaschineDefault }

    /// A copy outside the Applications folders (e.g. a build folder) must not become the default.
    static var isInstalled: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let folders = FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        return folders.contains { path.hasPrefix($0.resolvingSymlinksInPath().path + "/") }
    }

    nonisolated static func isSchreibmaschine(_ app: URL) -> Bool {
        Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// macOS asks the user to confirm each type, one dialog after the other, and cannot ask for
    /// several at once. Types the Schreibmaschine already has are skipped, and a single "keep"
    /// ends the whole run, so that declining does not mean declining a dozen times.
    static func makeDefault(for formats: [TextFormat] = TextFormat.all) async {
        var previous = previousApps
        run: for format in formats where !format.isSchreibmaschineDefault {
            for type in format.types {
                let current = NSWorkspace.shared.urlForApplication(toOpen: type)
                if let current, isSchreibmaschine(current) { continue }
                if let current { previous[type.identifier] = current.path }
                try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
                guard let now = NSWorkspace.shared.urlForApplication(toOpen: type), isSchreibmaschine(now) else { break run }
            }
        }
        defaults.set(previous, forKey: Key.previousApps)
        if isDefaultForAny { defaults.set(true, forKey: Key.wasDefault) }
    }

    /// Gives the formats back to the app they had before, or to TextEdit if that is unknown or
    /// gone. macOS cannot remove a default, only set another one; it asks to confirm each change,
    /// and as when setting, a single "keep" ends the run.
    static func restore(_ formats: [TextFormat] = TextFormat.available) async {
        var previous = previousApps
        run: for format in formats where format.isSchreibmaschineDefault {
            for type in format.types {
                guard let current = NSWorkspace.shared.urlForApplication(toOpen: type), isSchreibmaschine(current),
                      let app = restoreApplication(for: type)
                else { continue }
                try? await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
                guard let now = NSWorkspace.shared.urlForApplication(toOpen: type), !isSchreibmaschine(now) else { break run }
                previous[type.identifier] = nil
            }
        }
        defaults.set(previous, forKey: Key.previousApps)
    }

    /// The app a format goes back to; for several types, the one of the first.
    static func restoreApplication(for format: TextFormat) -> URL? {
        format.types.first.flatMap(restoreApplication(for:))
    }

    private static func restoreApplication(for type: UTType) -> URL? {
        if let path = previousApps[type.identifier], FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
    }

    private static var previousApps: [String: String] {
        defaults.dictionary(forKey: Key.previousApps) as? [String: String] ?? [:]
    }

    static func name(of application: URL) -> String {
        let name = FileManager.default.displayName(atPath: application.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    static func icon(of application: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: application.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    // MARK: Usage and offers

    /// Counts the days on which the Schreibmaschine was used.
    static func recordUsage() {
        let today = Date.now.formatted(.iso8601.year().month().day())
        guard defaults.string(forKey: Key.lastUsageDay) != today else { return }
        defaults.set(today, forKey: Key.lastUsageDay)
        defaults.set(defaults.integer(forKey: Key.usageDays) + 1, forKey: Key.usageDays)
    }

    /// Returns true if the offer should be shown now, and records that it was shown.
    static func claimOffer() -> Bool {
        guard !offeredThisSession, shouldOffer() else { return false }
        offeredThisSession = true
        defaults.set(defaults.integer(forKey: Key.offerCount) + 1, forKey: Key.offerCount)
        defaults.set(Date.now, forKey: Key.lastOfferDate)
        defaults.set(defaults.integer(forKey: Key.usageDays), forKey: Key.usageDaysAtLastOffer)
        return true
    }

    private static func shouldOffer() -> Bool {
        if isDefault {
            defaults.set(true, forKey: Key.wasDefault)
            return false
        }
        guard isInstalled, !defaults.bool(forKey: Key.wasDefault) else { return false }

        let usageDays = defaults.integer(forKey: Key.usageDays)
        switch defaults.integer(forKey: Key.offerCount) {
        case 0:
            return usageDays >= requiredUsageDays
        case ..<maxOffers:
            guard let last = defaults.object(forKey: Key.lastOfferDate) as? Date else { return false }
            let newUsageDays = usageDays - defaults.integer(forKey: Key.usageDaysAtLastOffer)
            return Date.now.timeIntervalSince(last) >= repeatAfter && newUsageDays >= requiredUsageDays
        default:
            return false
        }
    }

    /// Records the day of use and, when due, shows the offer below the title bar of the window.
    static func offerIfDue(in window: NSWindow) {
        recordUsage()
        guard claimOffer() else { return }
        showOffer(in: window)
    }

    static func showOffer(in window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .bottom
        accessory.view = NSHostingView(rootView: DefaultAppBanner { [weak accessory] in
            accessory?.removeFromParent()
        })
        window.addTitlebarAccessoryViewController(accessory)
    }
}

/// Unobtrusive bar below the title bar of a window.
struct DefaultAppBanner: View {
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text("Die Schreibmaschine als Standard-App für Text und Code verwenden?")
            Spacer(minLength: 8)
            Button("Als Standard festlegen") {
                Task {
                    await DefaultAppOffer.makeDefault()
                    onClose()
                }
            }
            .help("macOS fragt für jedes Format einzeln nach; lehnst du einmal ab, fragt die Schreibmaschine nicht weiter")
            Button("Nicht jetzt", action: onClose)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

/// Settings rows showing the current default app for text, with buttons to change it.
struct DefaultAppSettingsRows: View {
    @State private var summary = Summary.current
    @State private var showsFormats = false

    var body: some View {
        LabeledContent("Standard-App:") {
            HStack {
                if summary.isAll {
                    Label("Schreibmaschine", systemImage: "checkmark")
                } else {
                    Text(summary.text)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .help(summary.help)
                    Button("Als Standard festlegen") {
                        Task {
                            await DefaultAppOffer.makeDefault()
                            summary = .current
                        }
                    }
                    .disabled(!DefaultAppOffer.isInstalled)
                    .help("macOS fragt für jedes Format einzeln nach; lehnst du einmal ab, fragt die Schreibmaschine nicht weiter")
                }
            }
        }
        LabeledContent("Einzelne Formate:") {
            HStack {
                Button("Zurücksetzen") {
                    Task {
                        await DefaultAppOffer.restore()
                        summary = .current
                    }
                }
                .disabled(!summary.hasSchreibmaschine)
                .help("Gibt die Formate wieder den Apps, die sie vorher hatten, sonst TextEdit")
                Button("Anpassen …") { showsFormats = true }
                    .disabled(!DefaultAppOffer.isInstalled)
            }
        }
        .sheet(isPresented: $showsFormats, onDismiss: { summary = .current }) {
            DefaultAppFormatsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            summary = .current
        }
    }

    private struct Summary {
        var isAll = false
        var hasSchreibmaschine = false
        var text: String
        var help = ""

        @MainActor static var current: Summary {
            let formats = TextFormat.all
            let own = formats.filter(\.isSchreibmaschineDefault).count
            if own == formats.count { return Summary(isAll: true, hasSchreibmaschine: true, text: "Schreibmaschine") }
            if own > 0 || DefaultAppOffer.isDefaultForAny {
                // In the row "Default app:" the name goes without saying; it keeps the row on one line.
                return Summary(hasSchreibmaschine: true, text: String(localized: "\(own) von \(formats.count) Formaten"),
                               help: String(localized: "Die Schreibmaschine öffnet \(own) von \(formats.count) Formaten; „Anpassen …“ zeigt, welche."))
            }
            let names = Set(formats.compactMap { $0.currentApplication.map(DefaultAppOffer.name(of:)) })
            return Summary(text: names.count == 1 ? names.first! : String(localized: "Verschiedene Apps"))
        }
    }
}

/// Sheet listing each format with the app that opens it.
struct DefaultAppFormatsView: View {
    @Environment(\.dismiss) private var dismiss
    /// Changes when a default was set, so the rows read the system again.
    @State private var generation = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Standard-App nach Format")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(TextFormat.available) { format in
                        GridRow {
                            Text(format.title)
                                .fontWeight(.medium)
                            if let app = format.currentApplication {
                                Label {
                                    Text(DefaultAppOffer.name(of: app))
                                } icon: {
                                    Image(nsImage: DefaultAppOffer.icon(of: app))
                                }
                            } else {
                                Text("Keine").foregroundStyle(.secondary)
                            }
                            if format.isSchreibmaschineDefault {
                                let target = DefaultAppOffer.restoreApplication(for: format).map(DefaultAppOffer.name(of:)) ?? "TextEdit"
                                Button(String(localized: "Zurück zu \(target)")) {
                                    Task {
                                        await DefaultAppOffer.restore([format])
                                        generation += 1
                                    }
                                }
                                .controlSize(.small)
                                .gridColumnAlignment(.trailing)
                            } else {
                                Button("Schreibmaschine verwenden") {
                                    Task {
                                        await DefaultAppOffer.makeDefault(for: [format])
                                        generation += 1
                                    }
                                }
                                .controlSize(.small)
                                .gridColumnAlignment(.trailing)
                            }
                        }
                    }
                }
            .id(generation)
            Text("macOS fragt für jedes Format einzeln nach, bei allen Formaten also mehrmals hintereinander. Lehnst du einmal ab, fragt die Schreibmaschine nicht weiter. HTML, CSV und Protokolle gehören nicht zu „Alle Formate“, weil sie meist im Browser, in einer Tabellenkalkulation oder in der Konsole besser aufgehoben sind. Zurücksetzen gibt ein Format der App zurück, die es vorher hatte, sonst TextEdit.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Alle Formate") {
                    Task {
                        await DefaultAppOffer.makeDefault()
                        generation += 1
                    }
                }
                .disabled(DefaultAppOffer.isDefaultForAll)
                Button("Alle zurücksetzen") {
                    Task {
                        await DefaultAppOffer.restore()
                        generation += 1
                    }
                }
                .disabled(!DefaultAppOffer.isDefaultForAny)
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        // The buttons in the app's steel blue, as in Motiv's sheet in its petrol.
        .tint(Color("AccentColor"))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            generation += 1
        }
    }
}
