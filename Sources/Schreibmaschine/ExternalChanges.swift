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

/// Watches a file for changes by other programs. File coordination (NSFilePresenter) only hears
/// of programs that take part in it; git, vim or a script just write. A dispatch source on the
/// file sees every write. Saving atomically replaces the file, so after a rename or delete the
/// watcher opens the file at its path again.
final class FileWatcher {
    private let url: URL
    private var source: DispatchSourceFileSystemObject?
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit { source?.cancel() }

    private func start() {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .extend, .delete, .rename, .attrib],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            onChange()
            if events.contains(.delete) || events.contains(.rename) {
                // The file at the path is another one now, or will be in a moment.
                self.source?.cancel()
                self.source = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.source == nil else { return }
                    start()
                    onChange()
                }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }
}

extension TextDocument {
    /// What happened to the file on disk, as the bar in the window tells it.
    enum ExternalChange: Equatable {
        case modified, deleted
    }

    /// Starts or ends watching the file, as the document gets or changes its location.
    func watchFile() {
        fileWatcher = fileURL.map { url in
            FileWatcher(url: url) { [weak self] in self?.scheduleExternalCheck() }
        }
    }

    /// Several writes in a row, as when saving, are looked at together a moment later.
    func scheduleExternalCheck() {
        externalCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkForExternalChange() }
        externalCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Compares the file with the state the document last read or wrote. Unchanged documents
    /// take the new text; with changes of its own, the document asks in a bar.
    func checkForExternalChange() {
        guard let fileURL, !isSavingFile else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            guard externalChange != .deleted else { return }
            // The text is all that is left of the file; closing must not lose it.
            updateChangeCount(.changeDone)
            showExternalChange(.deleted)
            return
        }
        let date = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let date, date != fileModificationDate else {
            // Back after a deletion, as when a program saves by replacing the file.
            if externalChange == .deleted { showExternalChange(nil) }
            return
        }
        if isDocumentEdited {
            showExternalChange(.modified)
        } else {
            reloadFromDisk()
        }
    }

    /// Reads the file again in its encoding, keeping every view at its place as far as the new
    /// text allows.
    func reloadFromDisk() {
        guard let fileURL else { return }
        let states = editor?.positions()
        do {
            let data = try Data(contentsOf: fileURL)
            do {
                try load(data, as: encoding)
            } catch {
                try load(data, as: nil)
            }
            fileModificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            updateChangeCount(.changeCleared)
            showExternalChange(nil)
            if let states {
                // After the views have heard of the new text, which moves them to its start.
                DispatchQueue.main.async { [weak self] in self?.editor?.restore(positions: states) }
            }
        } catch {
            showExternalChange(.modified)
        }
    }

    /// After saving, the file is the document's own again.
    func clearExternalChange() {
        if externalChange != nil { showExternalChange(nil) }
    }

    /// Keeps the own text: the next save overwrites the file without asking again.
    func keepOwnText() {
        if let fileURL {
            fileModificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        showExternalChange(nil)
    }

    private func showExternalChange(_ change: ExternalChange?) {
        externalChange = change
        guard let window = windowControllers.first?.window else { return }
        for accessory in window.titlebarAccessoryViewControllers where accessory.view is NSHostingView<ExternalChangeBar> {
            accessory.removeFromParent()
        }
        guard let change else { return }
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .bottom
        accessory.view = NSHostingView(rootView: ExternalChangeBar(change: change, name: displayName, document: self))
        window.addTitlebarAccessoryViewController(accessory)
    }

    /// Looks at every open document when the app comes back to the front, in case a change
    /// slipped by while it was in the background.
    static func checkAllForExternalChanges() {
        for case let document as TextDocument in NSDocumentController.shared.documents {
            document.checkForExternalChange()
        }
    }
}

extension EditorViewController {
    /// Selection and first visible line of every pane, as character offsets.
    func positions() -> [(selection: NSRange, top: Int)] {
        panes.map { ($0.textView.selectedRange(), $0.topOffset) }
    }

    func restore(positions: [(selection: NSRange, top: Int)]) {
        let length = document.textStorage.length
        for (pane, position) in zip(panes, positions) {
            let location = min(position.selection.location, length)
            pane.textView.setSelectedRange(NSRange(location: location, length: min(position.selection.length, length - location)))
            pane.scroll(toOffset: min(position.top, length))
        }
    }
}

/// The bar below the title bar when the file changed on disk while the document has changes
/// of its own, or when the file is gone.
struct ExternalChangeBar: View {
    let change: TextDocument.ExternalChange
    let name: String
    let document: TextDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            switch change {
            case .modified:
                Text("„\(name)“ wurde außerhalb der Schreibmaschine geändert.")
                Spacer(minLength: 8)
                Button("Vergleichen") {
                    // The comparison is for merging into the own text, which saving then writes.
                    document.keepOwnText()
                    document.editor?.compareWithFileOnDisk(title: String(localized: "\(name) (extern geändert)"))
                }
                .help("Zeigt deinen Text neben der geänderten Datei; Unterschiede lassen sich übernehmen")
                Button("Neu laden") { document.reloadFromDisk() }
                    .help("Liest die Datei neu; deine ungesicherten Änderungen gehen verloren")
                Button("Behalten") { document.keepOwnText() }
                    .help("Behält deinen Text; Sichern überschreibt dann die geänderte Datei")
            case .deleted:
                Text("„\(name)“ wurde gelöscht oder verschoben. Dein Text bleibt erhalten.")
                Spacer(minLength: 8)
                Button("Sichern unter …") { document.saveAs(nil) }
            }
        }
        .lineLimit(1)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}
