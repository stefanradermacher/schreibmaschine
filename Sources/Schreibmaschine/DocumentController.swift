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
import UniformTypeIdentifiers

/// Every file is a text document, whatever its type; whether it holds text, reading it tells.
final class DocumentController: NSDocumentController {
    /// Set by the app delegate when launching is done.
    var isLaunching = true
    /// The app was started to open files; the session is then not restored.
    private(set) var openedFilesDuringLaunch = false

    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        if isLaunching { openedFilesDuringLaunch = true }
        super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
    }

    override func documentClass(forType typeName: String) -> AnyClass? {
        TextDocument.self
    }

    override func typeForContents(of url: URL) throws -> String {
        (try? super.typeForContents(of: url)) ?? UTType.plainText.identifier
    }

    override var defaultType: String? {
        UTType.plainText.identifier
    }

    /// Called when the app quits. Instead of asking about every unsaved document, the session
    /// keeps the unsaved texts; only if they cannot be written does the usual review run.
    override func reviewUnsavedDocuments(withAlertTitle title: String?, cancellable: Bool, delegate: Any?,
                                         didReviewAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        for case let document as TextDocument in documents { document.autosaveBeforeQuitting() }
        guard SessionStore.shared.save(cleanExit: true) else {
            return super.reviewUnsavedDocuments(withAlertTitle: title, cancellable: cancellable, delegate: delegate,
                                                didReviewAllSelector: didReviewAllSelector, contextInfo: contextInfo)
        }
        guard let delegate = delegate as AnyObject?, let selector = didReviewAllSelector else { return }
        // - (void)documentController:(NSDocumentController *)controller didReviewAll:(BOOL)didReviewAll contextInfo:(void *)contextInfo
        typealias DidReviewAll = @convention(c) (AnyObject, Selector, NSDocumentController, Bool, UnsafeMutableRawPointer?) -> Void
        let function = unsafeBitCast(delegate.method(for: selector), to: DidReviewAll.self)
        function(delegate, selector, self, true, contextInfo)
    }
}
