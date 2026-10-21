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

/// The bar below the text: position of the insertion point on the left, encoding and line
/// ending on the right, each changeable with a click.
final class StatusBar: NSView, NSMenuDelegate {
    private let position = NSTextField(labelWithString: "")
    private let countButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let languageButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let indentationButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let encodingButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let lineEndingButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private weak var document: TextDocument?

    init(document: TextDocument) {
        self.document = document
        super.init(frame: .zero)

        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        position.font = font
        position.textColor = .secondaryLabelColor
        position.lineBreakMode = .byTruncatingTail
        position.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for button in [countButton, languageButton, indentationButton, encodingButton, lineEndingButton] {
            button.isBordered = false
            button.font = font
            button.controlSize = .small
            (button.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        }
        countButton.toolTip = String(localized: "Wörter, Zeichen, Zeilen und Absätze; für die Auswahl getrennt")
        countButton.menu = NSMenu()
        countButton.menu?.addItem(NSMenuItem())
        languageButton.toolTip = String(localized: "Sprache für Hervorhebung, Kommentare und Einrückung")
        indentationButton.toolTip = String(localized: "Einrückung dieses Dokuments")
        encodingButton.toolTip = String(localized: "Zeichenkodierung beim Sichern")
        lineEndingButton.toolTip = String(localized: "Zeilenenden beim Sichern")
        buildMenus()

        let separator = NSBox()
        separator.boxType = .separator

        let stack = NSStackView(views: [position, countButton, NSView(), languageButton, indentationButton, encodingButton, lineEndingButton])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 6)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)

        for view in [separator, stack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: separator.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        updateFormat()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Pull-down menus: the first item is the button's title, the others are the choices.
    private func buildMenus() {
        // The languages are listed when the menu opens, so newly added ones appear.
        let languages = NSMenu()
        languages.addItem(NSMenuItem())
        languages.delegate = self
        languageButton.menu = languages

        let indentation = NSMenu()
        indentation.addItem(NSMenuItem())
        for (title, action, tag) in [
            (String(localized: "Mit Leerzeichen"), #selector(TextDocument.indentWithSpaces(_:)), 0),
            (String(localized: "Mit Tabs"), #selector(TextDocument.indentWithTabs(_:)), 0),
            ("-", nil, 0),
            (String(localized: "Breite 2"), #selector(TextDocument.changeIndentWidth(_:)), 2),
            (String(localized: "Breite 3"), #selector(TextDocument.changeIndentWidth(_:)), 3),
            (String(localized: "Breite 4"), #selector(TextDocument.changeIndentWidth(_:)), 4),
            (String(localized: "Breite 8"), #selector(TextDocument.changeIndentWidth(_:)), 8),
            ("-", nil, 0),
            (String(localized: "Einrückung der Datei erkennen"), #selector(TextDocument.redetectIndentation(_:)), 0),
        ] as [(String, Selector?, Int)] {
            if action == nil {
                indentation.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.tag = tag
            item.target = document
            indentation.addItem(item)
        }
        indentationButton.menu = indentation

        let encodings = NSMenu()
        encodings.addItem(NSMenuItem())
        for encoding in TextEncoding.menuItems {
            guard let encoding else {
                encodings.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: TextEncoding.name(of: encoding), action: #selector(encodingChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(encoding.rawValue)
            encodings.addItem(item)
        }
        encodings.addItem(.separator())
        encodings.addItem(TextEncoding.moreEncodingsItem { encoding in
            let item = NSMenuItem(title: TextEncoding.name(of: encoding), action: #selector(encodingChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(encoding.rawValue)
            return item
        })
        encodingButton.menu = encodings

        let endings = NSMenu()
        endings.addItem(NSMenuItem())
        for ending in LineEnding.allCases {
            let item = NSMenuItem(title: ending.name, action: #selector(lineEndingChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ending.rawValue
            endings.addItem(item)
        }
        lineEndingButton.menu = endings
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === languageButton.menu else { return }
        while menu.items.count > 1 { menu.removeItem(at: 1) }
        let plain = NSMenuItem(title: String(localized: "Reiner Text"), action: #selector(TextDocument.chooseLanguage(_:)), keyEquivalent: "")
        plain.representedObject = ""
        plain.target = document
        menu.addItem(plain)
        menu.addItem(.separator())
        for language in LanguageRegistry.shared.languages {
            let item = NSMenuItem(title: language.name, action: #selector(TextDocument.chooseLanguage(_:)), keyEquivalent: "")
            item.representedObject = language.id
            item.target = document
            menu.addItem(item)
        }
    }

    /// Shows the document's language, indentation, encoding and line ending.
    func updateFormat() {
        guard let document else { return }
        languageButton.menu?.items.first?.title = document.language?.name ?? String(localized: "Reiner Text")
        let indentation = document.indentation
        indentationButton.menu?.items.first?.title = indentation.usesSpaces
            ? String(localized: "Leerzeichen: \(indentation.width)")
            : String(localized: "Tabs: \(indentation.width)")
        languageButton.synchronizeTitleAndSelectedItem()
        indentationButton.synchronizeTitleAndSelectedItem()
        let bom = document.hasBOM ? String(localized: " mit BOM") : ""
        encodingButton.menu?.items.first?.title = TextEncoding.name(of: document.encoding) + bom
        // The current encoding gets a check mark; the groups of "More Encodings" that contain
        // it get a dash, so it can be found.
        let current = Int(document.encoding.rawValue)
        func mark(_ items: [NSMenuItem]) -> Bool {
            var contains = false
            for item in items {
                if let submenu = item.submenu {
                    let inside = mark(submenu.items)
                    item.state = inside ? .mixed : .off
                    contains = contains || inside
                } else if !item.isSeparatorItem {
                    item.state = item.tag == current ? .on : .off
                    contains = contains || item.tag == current
                }
            }
            return contains
        }
        _ = mark(Array(encodingButton.menu?.items.dropFirst() ?? []))

        let ending = document.lineEnding
        for item in lineEndingButton.menu?.items.dropFirst() ?? [] {
            item.state = item.representedObject as? String == ending.rawValue ? .on : .off
        }
        if document.hadMixedLineEndings {
            lineEndingButton.menu?.items.first?.title = String(localized: "Gemischt → \(ending.shortName)")
            lineEndingButton.toolTip = String(localized: "Die Datei hat unterschiedliche Zeilenenden. Beim Sichern bekommen alle Zeilen \(ending.shortName).")
        } else {
            lineEndingButton.menu?.items.first?.title = ending.shortName
            lineEndingButton.toolTip = String(localized: "Zeilenenden beim Sichern")
        }
        encodingButton.synchronizeTitleAndSelectedItem()
        lineEndingButton.synchronizeTitleAndSelectedItem()
    }

    /// Shows line and column of the insertion point, and the size of the selection.
    func updatePosition(line: Int, column: Int, selectedCharacters: Int, selectedLines: Int) {
        var text = String(localized: "Zeile \(line), Spalte \(column)")
        if selectedCharacters > 0 {
            text += "   "
            text += selectedLines > 1
                ? String(localized: "\(selectedCharacters) Zeichen in \(selectedLines) Zeilen ausgewählt")
                : String(localized: "\(selectedCharacters) Zeichen ausgewählt")
        }
        position.stringValue = text
    }

    // MARK: - Counting

    private var countUnit: TextStatistics.Unit {
        get { TextStatistics.Unit(rawValue: UserDefaults.standard.string(forKey: Preferences.statusCountUnit) ?? "") ?? .words }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Preferences.statusCountUnit) }
    }
    private var total = TextStatistics()
    private var selected: TextStatistics?
    private var pendingCount: DispatchWorkItem?
    private var countGeneration = 0

    /// Counts the text and the selection a moment after the last change, away from the main
    /// thread, so that typing in a long text is not slowed down.
    func updateCounts(text: String, selections: [NSRange]) {
        pendingCount?.cancel()
        countGeneration += 1
        let generation = countGeneration
        let selectedText = selections.contains { $0.length > 0 }
            ? selections.filter { $0.length > 0 }.map { (text as NSString).substring(with: $0) }.joined(separator: "\n")
            : nil
        let work = DispatchWorkItem { [weak self] in
            let total = TextStatistics(of: text)
            let selected = selectedText.map(TextStatistics.init(of:))
            DispatchQueue.main.async {
                guard let self, generation == self.countGeneration else { return }
                self.total = total
                self.selected = selected
                self.showCounts()
            }
        }
        pendingCount = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func showCounts() {
        guard let menu = countButton.menu else { return }
        func title(_ unit: TextStatistics.Unit) -> String {
            if let selected { return unit.part(selected.value(unit), of: total.value(unit)) }
            return unit.total(total.value(unit))
        }
        while menu.items.count > 1 { menu.removeItem(at: 1) }
        for unit in TextStatistics.Unit.allCases {
            let item = NSMenuItem(title: title(unit), action: #selector(countUnitChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = unit.rawValue
            item.state = unit == countUnit ? .on : .off
            menu.addItem(item)
        }
        menu.items.first?.title = title(countUnit)
        countButton.synchronizeTitleAndSelectedItem()
    }

    @objc private func countUnitChosen(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let unit = TextStatistics.Unit(rawValue: raw) {
            countUnit = unit
            showCounts()
        }
    }

    @objc private func encodingChosen(_ sender: NSMenuItem) {
        document?.changeEncoding(to: String.Encoding(rawValue: UInt(sender.tag)))
    }

    @objc private func lineEndingChosen(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let ending = LineEnding(rawValue: raw) {
            document?.changeLineEnding(to: ending)
        }
    }
}
