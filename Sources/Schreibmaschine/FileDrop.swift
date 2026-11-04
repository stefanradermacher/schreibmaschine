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

/// Files dragged from the Finder onto a window open as documents, as with File → Open. On the
/// text, ⌥ inserts their paths instead, as the text view would do by itself. Folders are not
/// taken.
enum FileDrop {
    /// Whether the drag holds files at all, folders included.
    static func hasFiles(_ info: NSDraggingInfo) -> Bool {
        info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: options)
    }

    /// The dragged files that can be opened: no folders and no packages.
    static func files(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true
        }
    }

    /// On the text, whether the drop opens the files rather than inserting their paths.
    static func opensInText(_ info: NSDraggingInfo) -> Bool {
        hasFiles(info) && !NSEvent.modifierFlags.contains(.option)
    }

    /// The operation to show while dragging: a copy if something can be opened, otherwise none.
    static func operation(_ info: NSDraggingInfo) -> NSDragOperation {
        files(info).isEmpty ? [] : .copy
    }

    /// Opens the dragged files; returns whether there was one.
    @discardableResult
    static func open(_ info: NSDraggingInfo) -> Bool {
        let urls = files(info)
        guard !urls.isEmpty else { return false }
        // After the drag has ended, so that the new windows come up in front of the Finder.
        DispatchQueue.main.async {
            NSApp.activate()
            for url in urls {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
            }
        }
        return true
    }

    private static let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
}
