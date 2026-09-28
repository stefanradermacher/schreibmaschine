import AppKit

/// The bar below the text: position of the insertion point on the left, encoding and line
/// ending on the right, each changeable with a click.
final class StatusBar: NSView {
    private let position = NSTextField(labelWithString: "")
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

        for button in [encodingButton, lineEndingButton] {
            button.isBordered = false
            button.font = font
            button.controlSize = .small
            (button.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        }
        encodingButton.toolTip = String(localized: "Zeichenkodierung beim Sichern")
        lineEndingButton.toolTip = String(localized: "Zeilenenden beim Sichern")
        buildMenus()

        let separator = NSBox()
        separator.boxType = .separator

        let stack = NSStackView(views: [position, NSView(), encodingButton, lineEndingButton])
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

    /// Shows the document's encoding and line ending.
    func updateFormat() {
        guard let document else { return }
        let bom = document.hasBOM ? String(localized: " mit BOM") : ""
        encodingButton.menu?.items.first?.title = TextEncoding.name(of: document.encoding) + bom
        for item in encodingButton.menu?.items.dropFirst() ?? [] {
            item.state = item.tag == Int(document.encoding.rawValue) ? .on : .off
        }

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

    @objc private func encodingChosen(_ sender: NSMenuItem) {
        document?.changeEncoding(to: String.Encoding(rawValue: UInt(sender.tag)))
    }

    @objc private func lineEndingChosen(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let ending = LineEnding(rawValue: raw) {
            document?.changeLineEnding(to: ending)
        }
    }
}
