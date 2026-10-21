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

/// The editor of a document in its window or tab: find bar, the text in one or two panes
/// (EditorPane.swift), the status bar, and the sidebar of the search in all documents.
///
/// The find bar and the status bar work with the pane that has the keyboard focus. The font
/// size belongs to the editor, because the panes share the text and with it the font.
final class EditorViewController: NSViewController, NSMenuItemValidation, NSSplitViewDelegate {
    let document: TextDocument
    private(set) var panes: [EditorPane] = []
    /// The pane the find bar and the status bar work with.
    private(set) var activePane: EditorPane!
    private let splitView = NSSplitView()
    /// The panes on the left, the Markdown preview on the right while it is shown.
    private let contentSplit = NSSplitView()
    private var preview: MarkdownPreview?
    private var previewHeadings: [Int] = []
    private var previewUpdate: DispatchWorkItem?
    private var previewObserver: NSObjectProtocol?
    private var statusBar: StatusBar!
    private(set) var search: SearchController!
    private var textAtTop: NSLayoutConstraint!
    private let allDocumentsView = AllDocumentsSearchView()
    private let documentList = DocumentListView()
    private var editorAtLeft: NSLayoutConstraint!
    private var editorBesideSidebar: NSLayoutConstraint!
    private var editorBesideList: NSLayoutConstraint!
    private var textBelowBar: NSLayoutConstraint!
    private var marksConstraints: [NSLayoutConstraint] = []
    private var textAboveStatusBar: NSLayoutConstraint!
    private var textToBottom: NSLayoutConstraint!
    private var observers: [NSObjectProtocol] = []

    /// Change of the font size against the settings, in points.
    private var zoom: CGFloat = 0

    /// The text view the find bar and other commands work with.
    var textView: EditorTextView { activePane.textView }

    init(document: TextDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func loadView() {
        splitView.dividerStyle = .thin
        splitView.delegate = self
        contentSplit.dividerStyle = .thin
        contentSplit.isVertical = true
        contentSplit.delegate = self
        contentSplit.addArrangedSubview(splitView)
        let first = makePane()
        activePane = first

        statusBar = StatusBar(document: document)
        search = SearchController(textView: first.textView, layoutManager: first.layoutManager, document: document)

        let container = NSView()   // the editor: find bar, text, status bar
        let bar = search.bar
        let marks = search.marksView
        for view in [bar, contentSplit, statusBar!, marks] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        // The text starts below the find bar while it is shown, at the top otherwise.
        textBelowBar = contentSplit.topAnchor.constraint(equalTo: bar.bottomAnchor)
        textAboveStatusBar = statusBar.topAnchor.constraint(equalTo: contentSplit.bottomAnchor)
        textToBottom = contentSplit.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        textAtTop = contentSplit.topAnchor.constraint(equalTo: container.topAnchor)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textAtTop,
            contentSplit.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentSplit.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textAboveStatusBar,
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            marks.widthAnchor.constraint(equalToConstant: 7),
        ])
        search.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            textAtTop.isActive = !visible
            textBelowBar.isActive = visible
        }

        // The search in all documents shows its results in a sidebar on the left; the document
        // list stands in the same place while the search is not active.
        let root = NSView()
        allDocumentsView.isHidden = true
        documentList.isHidden = true
        for view in [allDocumentsView, documentList, container] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        editorAtLeft = container.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        editorBesideSidebar = container.leadingAnchor.constraint(equalTo: allDocumentsView.trailingAnchor)
        editorBesideList = container.leadingAnchor.constraint(equalTo: documentList.trailingAnchor)
        NSLayoutConstraint.activate([
            documentList.topAnchor.constraint(equalTo: root.topAnchor),
            documentList.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            documentList.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            documentList.widthAnchor.constraint(equalToConstant: 220),
            allDocumentsView.topAnchor.constraint(equalTo: root.topAnchor),
            allDocumentsView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            allDocumentsView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            allDocumentsView.widthAnchor.constraint(equalToConstant: 300),
            editorAtLeft,
            container.topAnchor.constraint(equalTo: root.topAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        view = root
        attachMarks(to: first)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyFont()
        updateSidebar()
        updatePosition()

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                updateSidebar()
                if isDistractionFree { applyFocus() }
                if currentFont != lastFont || Preferences.lineHeightValue != lastLineHeight { applyFont() }
            },
            center.addObserver(forName: AllDocumentsSearch.didChange, object: nil, queue: .main) { [weak self] _ in
                self?.updateSidebar()
            },
            center.addObserver(forName: TextDocument.formatDidChange, object: document, queue: .main) { [weak self] _ in
                self?.statusBar.updateFormat()
            },
            center.addObserver(forName: TextDocument.textDidReload, object: document, queue: .main) { [weak self] _ in
                guard let self else { return }
                applyFont()
                panes.forEach { $0.textView.setSelectedRange(NSRange(location: 0, length: 0)) }
            },
            center.addObserver(forName: TextDocument.languageDidChange, object: document, queue: .main) { [weak self] _ in
                self?.statusBar.updateFormat()
            },
            center.addObserver(forName: TextDocument.indentationDidChange, object: document, queue: .main) { [weak self] _ in
                self?.applyFont()
                self?.statusBar.updateFormat()
            },
        ]
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
        if let state = pendingViewState {
            pendingViewState = nil
            apply(state)
        }
        #if DEBUG
        // For looking at the find bar without a keyboard: -DebugFindBar find|replace|goto
        // and -DebugFindText <text>.
        if let mode = UserDefaults.standard.string(forKey: "DebugFindBar") {
            search.show(mode == "replace" ? .replace : mode == "goto" ? .goToLine : .find)
            if let text = UserDefaults.standard.string(forKey: "DebugFindText") {
                search.bar.setSearchText(text)
                search.findBarQueryDidChange(search.bar)
            }
        }
        // For testing editing commands: -DebugScript "at:5|sel:selectNextOccurrence:|type:X|dump",
        // steps separated by |; the results go to the log.
        if let script = UserDefaults.standard.string(forKey: "DebugScript"), !Self.debugScriptDone {
            Self.debugScriptDone = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.runDebugScript(script) }
        }
        #endif
    }

    #if DEBUG
    private static var debugScriptDone = false

    private func runDebugScript(_ script: String) {
        let steps = script.components(separatedBy: "|")
        for (index, step) in steps.enumerated() {
            let (command, argument) = step.firstIndex(of: ":").map { (String(step[..<$0]), String(step[step.index(after: $0)...])) } ?? (step, "")
            if command == "wait" {
                // wait:3 — the rest runs later, while the app goes on working.
                let rest = steps[(index + 1)...].joined(separator: "|")
                DispatchQueue.main.asyncAfter(deadline: .now() + (Double(argument) ?? 1)) { [weak self] in self?.runDebugScript(rest) }
                return
            }
            let started = Date()
            defer {
                let elapsed = Date().timeIntervalSince(started)
                if elapsed > 0.1 { NSLog("DEBUGSCRIPT   %@ dauerte %.2f s", step, elapsed) }
            }
            switch command {
            case "at":
                let parts = argument.split(separator: ",").compactMap { Int($0) }
                textView.setSelectedRange(NSRange(location: parts[0], length: parts.count > 1 ? parts[1] : 0))
            case "scrollto":
                activePane.scroll(toOffset: Int(argument) ?? 0)
            case "scrolly":
                // scrolly:0.5 — like dragging the scroller to half the height
                let started = Date()
                guard let pane = activePane else { break }
                let clip = pane.scrollView.contentView
                let y = (Double(argument) ?? 0) * (pane.textView.frame.height - clip.bounds.height)
                clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
                pane.scrollView.reflectScrolledClipView(clip)
                pane.layoutManager.textViewportLayoutController.layoutViewport()
                NSLog("DEBUGSCRIPT scrolly %@ top=%d %.2f s", argument, pane.topOffset, Date().timeIntervalSince(started))
            case "line":
                textView.setSelectedRange(NSRange(location: document.lineIndex.start(ofLine: Int(argument) ?? 1), length: 0))
                textView.scrollRangeToVisible(textView.selectedRange())
            case "add":
                let parts = argument.split(separator: ",").compactMap { Int($0) }
                textView.setCursorRanges(textView.editingRanges + [NSRange(location: parts[0], length: parts.count > 1 ? parts[1] : 0)])
            case "key":
                textView.doCommand(by: NSSelectorFromString(argument))
            case "subtree":
                for window in NSApp.windows where window.title.contains(argument) {
                    if let text = window.contentView?.perform(NSSelectorFromString("_subtreeDescription"))?.takeUnretainedValue() as? String {
                        NSLog("DEBUGSCRIPT subtree\n%@", String(text.prefix(6000)))
                    }
                }
            case "takeover":
                // takeover:<block from 0>,left|right
                let parts = argument.split(separator: ",")
                if let compare = NSApp.windows.compactMap({ $0.contentViewController as? CompareViewController }).first,
                   let index = Int(parts[0]) {
                    compare.takeOver(index, toLeft: parts.last == "left")
                    NSLog("DEBUGSCRIPT takeover blocks=%d left=%@", compare.hunks.count,
                          String(compare.left.document.textStorage.string.prefix(60)))
                }
            case "geom":
                func walk(_ view: NSView) {
                    if let scroll = view as? NSScrollView, let ruler = scroll.verticalRulerView, let text = scroll.documentView as? NSTextView {
                        NSLog("DEBUGSCRIPT geom scroll %@ clip %@ bounds %@ ruler %@ dicke %.1f text %@ origin %@ sichtbar %d",
                              NSStringFromRect(scroll.frame), NSStringFromRect(scroll.contentView.frame), NSStringFromRect(scroll.contentView.bounds),
                              NSStringFromRect(ruler.frame), ruler.ruleThickness, NSStringFromRect(text.frame), NSStringFromPoint(text.textContainerOrigin), scroll.rulersVisible ? 1 : 0)
                    }
                    view.subviews.forEach(walk)
                }
                for window in NSApp.windows where window.title.contains(argument) { window.contentView.map(walk) }
            case "layoutall":
                let started = Date()
                activePane.layoutManager.ensureLayout(for: activePane.layoutManager.documentRange)
                NSLog("DEBUGSCRIPT layoutall %.2f s", Date().timeIntervalSince(started))
            case "press":
                // press:home, press:end+shift, press:home+cmd, press:pagedown
                let parts = argument.split(separator: "+").map(String.init)
                let keys = ["home": NSHomeFunctionKey, "end": NSEndFunctionKey, "pageup": NSPageUpFunctionKey, "pagedown": NSPageDownFunctionKey]
                guard let code = keys[parts[0]], let scalar = UnicodeScalar(code) else { break }
                var flags: NSEvent.ModifierFlags = [.function]
                if parts.contains("shift") { flags.insert(.shift) }
                if parts.contains("cmd") { flags.insert(.command) }
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                                windowNumber: view.window?.windowNumber ?? 0, context: nil,
                                                characters: String(Character(scalar)), charactersIgnoringModifiers: String(Character(scalar)),
                                                isARepeat: false, keyCode: 0) {
                    textView.keyDown(with: event)
                }
            case "script":
                // script:<file name in the scripts folder>
                if let folder = UserScript.folder {
                    let item = NSMenuItem()
                    item.representedObject = folder.appendingPathComponent(argument)
                    runUserScript(item)
                }
            case "frame":
                // frame:1440,900 — the window at that size, in the middle of the screen
                let size = argument.split(separator: ",").compactMap { Double($0) }
                if size.count == 2, let window = view.window, let screen = window.screen ?? NSScreen.main {
                    let visible = screen.visibleFrame
                    let frame = NSRect(x: visible.midX - size[0] / 2, y: visible.midY - size[1] / 2, width: size[0], height: size[1])
                    window.setFrame(frame, display: true)
                }
            case "find":
                showFindBar(nil)
                search.bar.searchField.stringValue = argument
                search.findBarQueryDidChange(search.bar)
            case "bookmark":
                document.toggleBookmark(atLine: Int(argument) ?? 1)
            case "top":
                activePane?.scroll(toOffset: document.lineIndex.start(ofLine: Int(argument) ?? 1))
            case "activate":
                NSApp.activate()
                view.window?.makeKeyAndOrderFront(nil)
            case "offer":
                if let window = view.window { DefaultAppOffer.showOffer(in: window) }
            case "formats":
                let sheet = NSHostingController(rootView: DefaultAppFormatsView())
                presentAsSheet(sheet)
            case "support":
                (NSApp.delegate as? AppDelegate)?.showSupport(nil)
            case "cmd":
                // cmd:<text command id>, as from the Text menu
                let item = NSMenuItem()
                item.representedObject = argument
                textView.performTextCommand(item)
            case "call":
                // call:<action> — straight to this editor, also when the window is not in front
                _ = perform(NSSelectorFromString(argument), with: nil)
            case "sel":
                NSApp.sendAction(NSSelectorFromString(argument), to: nil, from: nil)
            case "type":
                textView.insertText(argument.replacingOccurrences(of: "\\n", with: "\n"), replacementRange: NSRange(location: NSNotFound, length: 0))
            case "dump":
                let ranges = textView.editingRanges.map { "\($0.location),\($0.length)" }.joined(separator: " ")
                let caretY = textView.caretRect(at: textView.selectedRange().upperBound).minY - textView.visibleRect.minY
                let caretLine = document.lineIndex.lineNumber(at: textView.selectedRange().upperBound)
                NSLog("DEBUGSCRIPT %@ height=%.0f line=%d y=%.1f panes=%d active=%d ranges=[%@] marks=%@ folds=%@ text=%@", argument, textView.frame.height, caretLine, caretY, panes.count,
                      panes.firstIndex { $0 === activePane } ?? -1, ranges, document.bookmarkedLines.description,
                      document.foldedHeads.description, document.textStorage.length < 300 ? textView.string.debugDescription : "… top=\(activePane?.topOffset ?? -1) visibleLine=\(document.lineIndex.lineNumber(at: activePane?.topOffset ?? 0))")
            default:
                NSLog("DEBUGSCRIPT unknown step %@", step)
            }
        }
        NSLog("DEBUGSCRIPT done")
    }
    #endif

    // MARK: - Panes

    private func makePane() -> EditorPane {
        let pane = EditorPane(document: document)
        pane.onFocus = { [weak self] pane in self?.activate(pane) }
        pane.onScroll = { [weak self] pane in
            if pane === self?.activePane { self?.syncPreviewScroll() }
        }
        pane.onSelectionChange = { [weak self] pane in
            if pane === self?.activePane { self?.updatePosition() }
        }
        addChild(pane)
        splitView.addArrangedSubview(pane.view)
        pane.textView.onCancel = { [weak self] in
            guard let search = self?.search, search.isVisible else { return false }
            search.close()
            return true
        }
        panes.append(pane)
        if isDistractionFree { pane.distractionFreeColumn = textColumnWidth }
        if let font = lastFont { pane.takeFont(font, attributes: EditorStyle.attributes(font: font, tabWidth: document.indentation.width)) }
        return pane
    }

    private func activate(_ pane: EditorPane) {
        guard pane !== activePane else { return }
        activePane = pane
        search.retarget(textView: pane.textView, layoutManager: pane.layoutManager)
        attachMarks(to: pane)
        updatePosition()
        syncPreviewScroll()
    }

    /// The marks of the matches stand at the right edge of the pane being searched.
    private func attachMarks(to pane: EditorPane) {
        NSLayoutConstraint.deactivate(marksConstraints)
        let marks = search.marksView
        marksConstraints = [
            marks.topAnchor.constraint(equalTo: pane.scrollView.topAnchor, constant: 2),
            marks.bottomAnchor.constraint(equalTo: pane.scrollView.bottomAnchor, constant: -2),
            marks.trailingAnchor.constraint(equalTo: pane.scrollView.trailingAnchor, constant: -1),
        ]
        NSLayoutConstraint.activate(marksConstraints)
    }

    var isSplit: Bool { panes.count > 1 }

    /// Shows the text a second time, beside or below, starting where the current pane is.
    private func split(sideBySide: Bool, state: EditorPane.State? = nil, fraction: Double = 0.5) {
        if isSplit {
            splitView.isVertical = sideBySide
            splitView.adjustSubviews()
            setSplitFraction(fraction)
            return
        }
        let current = activePane.state
        splitView.isVertical = sideBySide
        let pane = makePane()
        splitView.layoutSubtreeIfNeeded()
        setSplitFraction(fraction)
        pane.apply(state ?? current)
        if state == nil {
            view.window?.makeFirstResponder(pane.textView)
        }
        SessionStore.shared.setNeedsSave()
    }

    private func setSplitFraction(_ fraction: Double) {
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        splitView.setPosition((total - splitView.dividerThickness) * CGFloat(fraction.clamped(to: 0.1...0.9)), ofDividerAt: 0)
    }

    private var splitFraction: Double {
        guard isSplit, let first = splitView.arrangedSubviews.first else { return 0.5 }
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        let size = splitView.isVertical ? first.frame.width : first.frame.height
        return total > 0 ? Double(size / (total - splitView.dividerThickness)) : 0.5
    }

    @objc func splitSideBySide(_ sender: Any?) { split(sideBySide: true) }
    @objc func splitStacked(_ sender: Any?) { split(sideBySide: false) }

    /// Closes the pane with the focus; the other one stays.
    @objc func closeSplit(_ sender: Any?) {
        guard isSplit, let index = panes.firstIndex(where: { $0 === activePane }) else { return }
        let closing = panes.remove(at: index)
        let remaining = panes[0]
        activate(remaining)
        if document.contentStorage.primaryTextLayoutManager === closing.layoutManager {
            document.contentStorage.primaryTextLayoutManager = remaining.layoutManager
        }
        closing.view.removeFromSuperview()
        closing.removeFromParent()
        view.window?.makeFirstResponder(remaining.textView)
        SessionStore.shared.setNeedsSave()
    }

    @objc func focusOtherPane(_ sender: Any?) {
        guard isSplit, let other = panes.first(where: { $0 !== activePane }) else { return NSSound.beep() }
        view.window?.makeFirstResponder(other.textView)
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        proposedMinimumPosition + 80
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        proposedMaximumPosition - 80
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        panes.forEach { $0.rewrapAfterResize() }
        SessionStore.shared.setNeedsSave()
    }

    // MARK: - Comparing

    private var currentSide: CompareSide {
        CompareSide(document: document, title: document.displayName, isReadOnly: false)
    }

    private func compare(with other: CompareSide) {
        CompareWindowController(left: currentSide, right: other).showWindow(nil)
    }

    /// A document only for the comparison, with a text and the language of this one.
    private func temporaryDocument(text: String) -> TextDocument {
        let other = TextDocument()
        other.restore(text: text, encoding: .utf8, hasBOM: false, lineEnding: .lf)
        other.setLanguage(document.language, byUser: false)
        return other
    }

    /// The text as it is saved on disk, against the text in the window.
    @objc func compareWithSaved(_ sender: Any?) {
        guard let url = document.fileURL, let type = document.fileType,
              let saved = try? TextDocument(contentsOf: url, ofType: type)
        else { return NSSound.beep() }
        compare(with: CompareSide(document: saved, title: String(localized: "\(document.displayName ?? "") (gesichert)"), isReadOnly: true))
    }

    @objc func compareWithClipboard(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return NSSound.beep() }
        compare(with: CompareSide(document: temporaryDocument(text: text.normalizingLineEndings),
                                  title: String(localized: "Zwischenablage"), isReadOnly: true))
    }

    /// An entry of "Compare With Document": its represented object is the other document.
    @objc func compareWithDocument(_ sender: NSMenuItem) {
        guard let other = sender.representedObject as? TextDocument else { return }
        compare(with: CompareSide(document: other, title: other.displayName, isReadOnly: false))
    }

    @objc func compareWithFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Mit welcher Datei vergleichen?")
        panel.prompt = String(localized: "Vergleichen")
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if let open = NSDocumentController.shared.document(for: url) as? TextDocument {
                compare(with: CompareSide(document: open, title: open.displayName, isReadOnly: false))
                return
            }
            do {
                let type = try NSDocumentController.shared.typeForContents(of: url)
                let other = try TextDocument(contentsOf: url, ofType: type)
                compare(with: CompareSide(document: other, title: other.displayName, isReadOnly: false))
            } catch {
                presentError(error)
            }
        }
    }

    // MARK: - Markdown preview

    var showsPreview: Bool { preview != nil }

    /// ⌥⌘P: the Markdown preview beside the text, or away again.
    @objc func togglePreview(_ sender: Any?) {
        showsPreview ? hidePreview() : showPreview()
        SessionStore.shared.setNeedsSave()
    }

    private func showPreview(fraction: Double = 0.5) {
        guard preview == nil else { return }
        let preview = MarkdownPreview(baseURL: document.fileURL?.deletingLastPathComponent())
        self.preview = preview
        contentSplit.addArrangedSubview(preview)
        contentSplit.layoutSubtreeIfNeeded()
        contentSplit.setPosition((contentSplit.bounds.width - contentSplit.dividerThickness) * CGFloat(fraction.clamped(to: 0.2...0.8)), ofDividerAt: 0)
        renderPreview()
        // The preview follows the text a moment after each change.
        previewObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: document.textStorage, queue: .main
        ) { [weak self] _ in
            guard let self, document.textStorage.editedMask.contains(.editedCharacters) else { return }
            previewUpdate?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.renderPreview() }
            previewUpdate = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    private func hidePreview() {
        previewUpdate?.cancel()
        if let previewObserver { NotificationCenter.default.removeObserver(previewObserver) }
        previewObserver = nil
        preview?.removeFromSuperview()
        preview = nil
        view.window?.makeFirstResponder(textView)
    }

    private func renderPreview() {
        guard let preview else { return }
        let text = document.textStorage.string
        previewHeadings = MarkdownRenderer.headingLines(in: text)
        let folder = document.fileURL?.deletingLastPathComponent()
        preview.show(html: MarkdownRenderer.html(from: text) { url in Self.imageSource(url, relativeTo: folder) })
        syncPreviewScroll()
    }

    /// The preview shows the place of the text at the top of the active pane, measured between
    /// the headings around it.
    private func syncPreviewScroll() {
        guard let preview else { return }
        let lineIndex = document.lineIndex
        let line = lineIndex.lineNumber(at: activePane.topOffset)
        let index = previewHeadings.lastIndex { $0 <= line }.map { $0 + 1 } ?? 0
        let start = index == 0 ? 1 : previewHeadings[index - 1]
        let end = index < previewHeadings.count ? previewHeadings[index] : lineIndex.lineCount + 1
        let fraction = end > start ? Double(line - start) / Double(end - start) : 0
        preview.scroll(betweenHeading: index, fraction: fraction)
    }

    /// An image of the document as a data URL, if the app may read it. In the sandbox that is
    /// usually not the case for files next to the document; images from the web are never loaded.
    private static func imageSource(_ url: URL, relativeTo folder: URL?) -> String? {
        if url.scheme == "data" { return url.absoluteString }
        guard url.scheme == nil || url.isFileURL, let folder else { return nil }
        let file = url.isFileURL ? url : URL(fileURLWithPath: url.relativeString.removingPercentEncoding ?? url.relativeString, relativeTo: folder)
        guard let data = try? Data(contentsOf: file), data.count < 20_000_000 else { return nil }
        let types = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
                     "svg": "image/svg+xml", "webp": "image/webp", "heic": "image/heic"]
        guard let type = types[file.pathExtension.lowercased()] else { return nil }
        return "data:\(type);base64,\(data.base64EncodedString())"
    }

    private var previewFraction: Double {
        guard let first = contentSplit.arrangedSubviews.first, contentSplit.bounds.width > 0 else { return 0.5 }
        return Double(first.frame.width / (contentSplit.bounds.width - contentSplit.dividerThickness))
    }

    // MARK: - Distraction-free mode

    /// Full screen without status bar, sidebars and line numbers, the text in a narrow column.
    private(set) var isDistractionFree = false
    /// Whether entering the mode also made the window full screen, so leaving it ends that too.
    private var enteredFullScreen = false
    private var fullScreenObserver: NSObjectProtocol?

    /// The width of the text column, from the setting in characters.
    private var textColumnWidth: CGFloat {
        (EditorStyle.spaceWidth(of: currentFont) * CGFloat(Preferences.textColumnValue) + 8).rounded()
    }

    @objc func toggleDistractionFree(_ sender: Any?) {
        isDistractionFree ? leaveDistractionFree(endFullScreen: true) : enterDistractionFree()
    }

    private func enterDistractionFree() {
        guard let window = view.window else { return }
        isDistractionFree = true
        search.close()
        textAboveStatusBar.isActive = false
        statusBar.isHidden = true
        textToBottom.isActive = true
        updateSidebar()
        applyFocus()
        enteredFullScreen = !window.styleMask.contains(.fullScreen)
        if enteredFullScreen { window.toggleFullScreen(nil) }
        // Leaving full screen in any other way ends the mode as well.
        fullScreenObserver = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.leaveDistractionFree(endFullScreen: false)
        }
        view.window?.makeFirstResponder(textView)
    }

    private func leaveDistractionFree(endFullScreen: Bool) {
        guard isDistractionFree else { return }
        isDistractionFree = false
        if let fullScreenObserver { NotificationCenter.default.removeObserver(fullScreenObserver) }
        fullScreenObserver = nil
        textToBottom.isActive = false
        statusBar.isHidden = false
        textAboveStatusBar.isActive = true
        panes.forEach { $0.distractionFreeColumn = nil }
        updateSidebar()
        if endFullScreen, enteredFullScreen, let window = view.window, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        enteredFullScreen = false
    }

    private func applyFocus() {
        let width = textColumnWidth
        panes.forEach { $0.distractionFreeColumn = width }
    }

    // MARK: - View state

    /// Applied when the view first appears: the state the file was last shown with.
    var pendingViewState: ViewState?

    var viewState: ViewState {
        if let pendingViewState { return pendingViewState }
        let first = panes[0].state
        var state = ViewState(
            selectionLocation: first.selectionLocation, selectionLength: first.selectionLength, topOffset: first.topOffset,
            wrapsLines: first.wrapsLines, showsLineNumbers: first.showsLineNumbers, showsInvisibles: first.showsInvisibles,
            zoom: Double(zoom), bookmarks: document.bookmarkedLines, folds: document.foldedHeads)
        if showsPreview { state.preview = previewFraction }
        if isSplit {
            state.split = SplitState(sideBySide: splitView.isVertical, second: panes[1].state, fraction: splitFraction)
        }
        return state
    }

    private func apply(_ state: ViewState) {
        if CGFloat(state.zoom) != zoom { setZoom(CGFloat(state.zoom)) }
        if let bookmarks = state.bookmarks, document.bookmarks.isEmpty { document.setBookmarkedLines(bookmarks) }
        if let folds = state.folds, !folds.isEmpty, document.folds.isEmpty { document.setFoldedHeads(folds) }
        panes[0].apply(EditorPane.State(
            selectionLocation: state.selectionLocation, selectionLength: state.selectionLength, topOffset: state.topOffset,
            wrapsLines: state.wrapsLines, showsLineNumbers: state.showsLineNumbers, showsInvisibles: state.showsInvisibles))
        if let splitState = state.split {
            split(sideBySide: splitState.sideBySide, state: splitState.second, fraction: splitState.fraction)
        }
        if let fraction = state.preview { showPreview(fraction: fraction) }
    }

    // MARK: - Font

    private var lastFont: NSFont?
    private var lastLineHeight = Preferences.lineHeightValue

    private var currentFont: NSFont {
        let base = Preferences.font
        return NSFont(descriptor: base.fontDescriptor, size: (base.pointSize + zoom).clamped(to: 6...96)) ?? base
    }

    private func applyFont() {
        let font = currentFont
        lastFont = font
        lastLineHeight = Preferences.lineHeightValue
        let attributes = EditorStyle.attributes(font: font, tabWidth: document.indentation.width)
        let storage = document.textStorage
        storage.beginEditing()
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        panes.forEach { $0.takeFont(font, attributes: attributes) }
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(zoom + 1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(zoom - 1) }
    @objc func resetZoom(_ sender: Any?) { setZoom(0) }

    private func setZoom(_ value: CGFloat) {
        let base = Preferences.font.pointSize
        let tops = panes.map { ($0, $0.topOffset) }
        zoom = (base + value).clamped(to: 6...96) - base
        applyFont()
        guard view.window != nil else { return }
        for (pane, top) in tops {
            pane.textView.layoutSubtreeIfNeeded()
            pane.scroll(toOffset: top)
        }
    }

    // MARK: - Status

    private func updatePosition() {
        let textView = textView
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let lineIndex = document.lineIndex
        let line = lineIndex.lineNumber(at: selection.location)
        let lineStart = lineIndex.start(ofLine: line)
        // Characters as the reader counts them, not UTF-16 units; long lines are counted in units.
        let prefix = NSRange(location: lineStart, length: selection.location - lineStart)
        let column = (prefix.length < 10_000 ? text.substring(with: prefix).count : prefix.length) + 1
        var selectedCharacters = 0
        var selectedLines = 0
        if selection.length > 0 {
            let selected = textView.selectedRanges.map(\.rangeValue)
            selectedCharacters = selected.reduce(0) { $0 + ($1.length < 100_000 ? text.substring(with: $1).count : $1.length) }
            let last = selection.upperBound - 1
            selectedLines = lineIndex.lineNumber(at: last) - line + 1
        }
        statusBar.updatePosition(line: line, column: column, selectedCharacters: selectedCharacters, selectedLines: selectedLines)
        statusBar.updateCounts(text: textView.string, selections: textView.editingRanges)
    }

    // MARK: - Find menu

    @objc func showFindBar(_ sender: Any?) { search.show(.find) }
    @objc func showReplaceBar(_ sender: Any?) { search.show(.replace) }
    @objc func showGoToLine(_ sender: Any?) { search.show(.goToLine) }
    @objc func findNextMatch(_ sender: Any?) { search.findNext(backwards: false) }
    @objc func findPreviousMatch(_ sender: Any?) { search.findNext(backwards: true) }
    @objc func selectAllMatches(_ sender: Any?) { search.selectAll() }
    @objc func useSelectionForFind(_ sender: Any?) { search.useSelection() }

    @objc func showAllDocumentsSearch(_ sender: Any?) {
        let selection = textView.selectedRange()
        var text: String?
        if selection.length > 0, selection.length < 2000 {
            text = (textView.string as NSString).substring(with: selection)
        } else if AllDocumentsSearch.shared.text.isEmpty {
            text = search.bar.searchField.stringValue.isEmpty ? SearchController.findPasteboardText : search.bar.searchField.stringValue
        }
        AllDocumentsSearch.shared.activate(with: text)
        allDocumentsView.focus()
    }

    private func updateSidebar() {
        let active = AllDocumentsSearch.shared.isActive && !isDistractionFree
        let showsList = !active && !isDistractionFree && UserDefaults.standard.bool(forKey: Preferences.showsDocumentList)
        guard allDocumentsView.isHidden == active || documentList.isHidden == showsList else { return }
        allDocumentsView.isHidden = !active
        documentList.isHidden = !showsList
        editorAtLeft.isActive = false
        editorBesideSidebar.isActive = false
        editorBesideList.isActive = false
        (active ? editorBesideSidebar : showsList ? editorBesideList : editorAtLeft).isActive = true
        if !active, view.window?.firstResponder is NSTextView, !panes.contains(where: { view.window?.firstResponder === $0.textView }) {
            view.window?.makeFirstResponder(textView)
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(resetZoom(_:)):
            return zoom != 0
        case #selector(splitSideBySide(_:)):
            item.state = isSplit && splitView.isVertical ? .on : .off
        case #selector(splitStacked(_:)):
            item.state = isSplit && !splitView.isVertical ? .on : .off
        case #selector(compareWithSaved(_:)):
            return document.fileURL != nil
        case #selector(compareWithClipboard(_:)):
            return NSPasteboard.general.string(forType: .string) != nil
        case #selector(togglePreview(_:)):
            item.state = showsPreview ? .on : .off
            return showsPreview || document.language?.id == "markdown"
        case #selector(toggleDistractionFree(_:)):
            item.state = isDistractionFree ? .on : .off
        case #selector(closeSplit(_:)), #selector(focusOtherPane(_:)):
            return isSplit
        default:
            break
        }
        return true
    }
}
