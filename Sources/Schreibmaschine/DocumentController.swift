import AppKit
import UniformTypeIdentifiers

/// Every file is a text document, whatever its type; whether it holds text, reading it tells.
final class DocumentController: NSDocumentController {
    override func documentClass(forType typeName: String) -> AnyClass? {
        TextDocument.self
    }

    override func typeForContents(of url: URL) throws -> String {
        (try? super.typeForContents(of: url)) ?? UTType.plainText.identifier
    }

    override var defaultType: String? {
        UTType.plainText.identifier
    }
}
