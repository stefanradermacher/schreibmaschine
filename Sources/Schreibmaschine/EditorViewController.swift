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
        let first = makePane()
        activePane = first

        statusBar = StatusBar(document: document)
        search = SearchController(textView: first.textView, layoutManager: first.layoutManager, document: document)

        let container = NSView()   // the editor: find bar, text, status bar
        let bar = search.bar
        let marks = search.marksView
        for view in [bar, splitView, statusBar!, marks] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        // The text starts below the find bar while it is shown, at the top otherwise.
        textBelowBar = splitView.topAnchor.constraint(equalTo: bar.bottomAnchor)
        textAtTop = splitView.topAnchor.constraint(equalTo: container.topAnchor)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textAtTop,
            splitView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.topAnchor.constraint(equalTo: splitView.bottomAnchor),
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
                if currentFont != lastFont { applyFont() }
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
        for step in script.components(separatedBy: "|") {
            let (command, argument) = step.firstIndex(of: ":").map { (String(step[..<$0]), String(step[step.index(after: $0)...])) } ?? (step, "")
            switch command {
            case "at":
                let parts = argument.split(separator: ",").compactMap { Int($0) }
                textView.setSelectedRange(NSRange(location: parts[0], length: parts.count > 1 ? parts[1] : 0))
            case "line":
                textView.setSelectedRange(NSRange(location: document.lineIndex.start(ofLine: Int(argument) ?? 1), length: 0))
                textView.scrollRangeToVisible(textView.selectedRange())
            case "add":
                let parts = argument.split(separator: ",").compactMap { Int($0) }
                textView.setCursorRanges(textView.editingRanges + [NSRange(location: parts[0], length: parts.count > 1 ? parts[1] : 0)])
            case "key":
                textView.doCommand(by: NSSelectorFromString(argument))
            case "sel":
                NSApp.sendAction(NSSelectorFromString(argument), to: nil, from: nil)
            case "type":
                textView.insertText(argument.replacingOccurrences(of: "\\n", with: "\n"), replacementRange: NSRange(location: NSNotFound, length: 0))
            case "dump":
                let ranges = textView.editingRanges.map { "\($0.location),\($0.length)" }.joined(separator: " ")
                NSLog("DEBUGSCRIPT %@ panes=%d active=%d ranges=[%@] marks=%@ folds=%@ text=%@", argument, panes.count,
                      panes.firstIndex { $0 === activePane } ?? -1, ranges, document.bookmarkedLines.description,
                      document.foldedHeads.description, textView.string.count < 300 ? textView.string.debugDescription : "…")
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
        if let font = lastFont { pane.takeFont(font, attributes: EditorStyle.attributes(font: font, tabWidth: document.indentation.width)) }
        return pane
    }

    private func activate(_ pane: EditorPane) {
        guard pane !== activePane else { return }
        activePane = pane
        search.retarget(textView: pane.textView, layoutManager: pane.layoutManager)
        attachMarks(to: pane)
        updatePosition()
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
        SessionStore.shared.setNeedsSave()
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
    }

    // MARK: - Font

    private var lastFont: NSFont?

    private var currentFont: NSFont {
        let base = Preferences.font
        return NSFont(descriptor: base.fontDescriptor, size: (base.pointSize + zoom).clamped(to: 6...96)) ?? base
    }

    private func applyFont() {
        let font = currentFont
        lastFont = font
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
        let active = AllDocumentsSearch.shared.isActive
        let showsList = !active && UserDefaults.standard.bool(forKey: Preferences.showsDocumentList)
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
        case #selector(closeSplit(_:)), #selector(focusOtherPane(_:)):
            return isSplit
        default:
            break
        }
        return true
    }
}
