import Foundation

/// Turns Markdown into HTML for the preview, with the Markdown reader built into macOS
/// (`AttributedString(markdown:)`), so the app needs no parser of its own or from others.
///
/// The reader marks every run of text with the blocks it stands in (list, list item, paragraph
/// …) and its inline style; the blocks are opened and closed here as the runs go by. Task list
/// items ("- [ ] …") come through as plain text and get their check boxes here. Headings are
/// numbered, so the preview can follow the scroll position of the text.
enum MarkdownRenderer {
    /// `image` turns the address of an image into what the page can show (a data URL), or nil
    /// when the image cannot be read; then its description stands in for it.
    static func html(from markdown: String, image: @escaping (URL) -> String? = { _ in nil }) -> String {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let document = try? AttributedString(markdown: markdown, options: options) else {
            return "<pre>" + escape(markdown) + "</pre>"
        }
        var renderer = Builder(resolveImage: image)
        for run in document.runs {
            renderer.add(text: String(document[run.range].characters),
                         blocks: run.presentationIntent?.components.reversed() ?? [],
                         inline: run.inlinePresentationIntent ?? [],
                         link: run.link,
                         image: run.imageURL)
        }
        return renderer.finish()
    }

    /// The lines of the Markdown source that are headings, outside code blocks: the anchors
    /// for following the scroll position.
    static func headingLines(in markdown: String) -> [Int] {
        var lines: [Int] = []
        var inFence = false
        var number = 0
        markdown.enumerateLines { line, _ in
            number += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle(); return }
            guard !inFence, line.hasPrefix("#") else { return }
            let hashes = line.prefix { $0 == "#" }.count
            if hashes <= 6, line.dropFirst(hashes).first == " " { lines.append(number) }
        }
        return lines
    }

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }

    private struct Builder {
        let resolveImage: (URL) -> String?
        private var html = ""
        /// The blocks open at the moment, outermost first.
        private var open: [PresentationIntent.IntentType] = []
        private var tableColumns: [PresentationIntent.TableColumn] = []
        private var headingCount = 0
        private var startsListItem = false
        private var inTableBody = false

        mutating func add(text: String, blocks: [PresentationIntent.IntentType], inline: InlinePresentationIntent,
                          link: URL?, image: URL?) {
            // Close the blocks this run is no longer in, open the new ones.
            var common = 0
            while common < open.count, common < blocks.count, open[common].identity == blocks[common].identity { common += 1 }
            while open.count > common { close(open.removeLast()) }
            for block in blocks[common...] {
                openBlock(block)
                open.append(block)
            }
            if case .codeBlock = blocks.last?.kind {
                html += escape(text)
                return
            }
            if case .thematicBreak = blocks.last?.kind { return }
            html += inlineHTML(text, inline: inline, link: link, image: image)
        }

        private mutating func inlineHTML(_ text: String, inline: InlinePresentationIntent, link: URL?, image: URL?) -> String {
            var text = text
            // A task list item: its first text begins with "[ ] " or "[x] ".
            var checkbox = ""
            if startsListItem {
                startsListItem = false
                for (marker, checked) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where text.hasPrefix(marker) {
                    text.removeFirst(marker.count)
                    checkbox = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")> "
                    if let index = html.range(of: "<li>", options: .backwards) {
                        html.replaceSubrange(index, with: "<li class=\"task\">")
                    }
                }
            }
            if let image {
                guard let source = resolveImage(image) else {
                    return checkbox + "<span class=\"missing-image\" title=\"\(escape(image.relativeString))\">\(escape(text.isEmpty ? image.lastPathComponent : text))</span>"
                }
                return checkbox + "<img src=\"\(escape(source))\" alt=\"\(escape(text))\">"
            }
            if inline.contains(.lineBreak) { return checkbox + "<br>" }
            if inline.contains(.softBreak) { return checkbox + "\n" }
            if inline.contains(.inlineHTML) || inline.contains(.blockHTML) {
                // Raw HTML is shown as text, not run: the preview runs no code from the document.
                return checkbox + "<code>" + escape(text) + "</code>"
            }
            var result = escape(text)
            if inline.contains(.code) { result = "<code>\(result)</code>" }
            if inline.contains(.strikethrough) { result = "<del>\(result)</del>" }
            if inline.contains(.emphasized) { result = "<em>\(result)</em>" }
            if inline.contains(.stronglyEmphasized) { result = "<strong>\(result)</strong>" }
            if let link { result = "<a href=\"\(escape(link.absoluteString))\">\(result)</a>" }
            return checkbox + result
        }

        private mutating func openBlock(_ block: PresentationIntent.IntentType) {
            switch block.kind {
            case .paragraph: html += "<p>"
            case .header(let level):
                headingCount += 1
                html += "<h\(level) id=\"h\(headingCount)\">"
            case .orderedList: html += "<ol>"
            case .unorderedList: html += "<ul>"
            case .listItem:
                html += "<li>"
                startsListItem = true
            case .codeBlock(let language):
                let attribute = language.map { " class=\"language-\(escape($0))\"" } ?? ""
                html += "<pre><code\(attribute)>"
            case .blockQuote: html += "<blockquote>"
            case .thematicBreak: html += "<hr>"
            case .table(let columns):
                tableColumns = columns
                inTableBody = false
                html += "<table>"
            case .tableHeaderRow: html += "<thead><tr>"
            case .tableRow:
                if !inTableBody { html += "<tbody>"; inTableBody = true }
                html += "<tr>"
            case .tableCell(let column):
                let header = open.last.map { if case .tableHeaderRow = $0.kind { true } else { false } } ?? false
                let alignment = column < tableColumns.count ? tableColumns[column].alignment : .left
                let style = switch alignment {
                case .center: " style=\"text-align:center\""
                case .right: " style=\"text-align:right\""
                default: ""
                }
                html += header ? "<th\(style)>" : "<td\(style)>"
            @unknown default: break
            }
        }

        private mutating func close(_ block: PresentationIntent.IntentType) {
            switch block.kind {
            case .paragraph: html += "</p>\n"
            case .header(let level): html += "</h\(level)>\n"
            case .orderedList: html += "</ol>\n"
            case .unorderedList: html += "</ul>\n"
            case .listItem: html += "</li>\n"
            case .codeBlock: html += "</code></pre>\n"
            case .blockQuote: html += "</blockquote>\n"
            case .thematicBreak: break
            case .table: html += (inTableBody ? "</tbody>" : "") + "</table>\n"
            case .tableHeaderRow: html += "</tr></thead>\n"
            case .tableRow: html += "</tr>\n"
            case .tableCell:
                let header = open.last.map { if case .tableHeaderRow = $0.kind { true } else { false } } ?? false
                html += header ? "</th>" : "</td>"
            @unknown default: break
            }
        }

        mutating func finish() -> String {
            while let block = open.popLast() { close(block) }
            return html
        }
    }
}
