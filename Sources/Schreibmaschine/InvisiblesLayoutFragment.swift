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

/// A paragraph that can draw its invisible characters: spaces, tabs, line breaks, no-break and
/// other special spaces, and characters without width.
final class InvisiblesLayoutFragment: NSTextLayoutFragment {
    /// Shared by all fragments of a view, so switching needs no new layout, only a redraw.
    final class Options {
        var showsInvisibles = false
    }

    var options: Options?

    /// Extra space below the paragraph, only in the layout of this view: in the comparison it
    /// stands for lines the other side has and this one has not.
    var extraHeight: CGFloat = 0

    override var layoutFragmentFrame: CGRect {
        var frame = super.layoutFragmentFrame
        frame.size.height += extraHeight
        return frame
    }

    /// How deep the paragraph is quoted in formatted Markdown.
    private var quoteDepth: Int {
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else { return 0 }
        return paragraph.attributedString.attribute(MarkdownStyler.quoteDepth, at: 0, effectiveRange: nil) as? Int ?? 0
    }

    /// A bar left of each level of a quoted line in formatted Markdown, over the whole height of
    /// the paragraph, so that the bars of a quote join up. The fragment starts where the text
    /// does, after the room the styler left for the bars.
    private func drawQuoteBars(at point: CGPoint, in context: CGContext) {
        let depth = quoteDepth
        guard depth > 0 else { return }
        // Down to the last line with text: the last paragraph of a text ending in a line break
        // also holds the empty line after it.
        let height = textLineFragments.last { $0.characterRange.length > 0 }?.typographicBounds.maxY
            ?? super.layoutFragmentFrame.height
        context.saveGState()
        context.setFillColor(NSColor.tertiaryLabelColor.cgColor)
        for level in 0..<depth {
            let x = point.x - CGFloat(depth - level) * MarkdownStyler.quoteBarStep + 2
            context.fill(CGRect(x: x, y: point.y, width: 3, height: height))
        }
        context.restoreGState()
    }

    private static func symbol(for character: unichar) -> String? {
        switch character {
        case 0x20: "·"
        case 0x09: "→"
        case 0x0A: "¬"
        case 0xA0, 0x202F: "°"                      // no-break spaces
        case 0x3000: "□"                            // ideographic space
        case 0x2000...0x200A, 0x205F: "∙"           // other spaces
        case 0x200B...0x200D, 0x2060, 0xFEFF: "◊"   // zero-width characters
        case 0x00...0x08, 0x0B...0x1F, 0x7F: "¿"    // control characters
        default: nil
        }
    }

    // The line break mark sits behind the last character and may stick out of the text. The
    // bounds do not depend on the option, so switching it needs no new layout.
    override var renderingSurfaceBounds: CGRect {
        let bounds = super.renderingSurfaceBounds
        // Quote bars lie left of the fragment.
        let left = CGFloat(quoteDepth) * MarkdownStyler.quoteBarStep
        return CGRect(x: bounds.minX - left, y: bounds.minY, width: bounds.width + 20 + left, height: bounds.height)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        drawQuoteBars(at: point, in: context)
        super.draw(at: point, in: context)
        guard options?.showsInvisibles == true else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }

        for line in textLineFragments {
            let string = line.attributedString.string as NSString
            let range = line.characterRange
            guard range.length > 0 else { continue }
            for index in range.location..<range.upperBound {
                guard let symbol = Self.symbol(for: string.character(at: index)) else { continue }
                let font = line.attributedString.attribute(.font, at: index, effectiveRange: nil) as? NSFont
                    ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                let position = line.locationForCharacter(at: index)
                let origin = CGPoint(
                    x: point.x + line.typographicBounds.minX + position.x,
                    y: point.y + line.typographicBounds.minY)
                (symbol as NSString).draw(at: origin, withAttributes: [
                    .font: font,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ])
            }
        }
    }
}
