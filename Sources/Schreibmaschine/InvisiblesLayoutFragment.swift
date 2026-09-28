import AppKit

/// A paragraph that can draw its invisible characters: spaces, tabs, line breaks, no-break and
/// other special spaces, and characters without width.
final class InvisiblesLayoutFragment: NSTextLayoutFragment {
    /// Shared by all fragments of a view, so switching needs no new layout, only a redraw.
    final class Options {
        var showsInvisibles = false
    }

    var options: Options?

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

    // The line break mark sits behind the last character and may stick out of the text.
    override var renderingSurfaceBounds: CGRect {
        let bounds = super.renderingSurfaceBounds
        guard options?.showsInvisibles == true else { return bounds }
        return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width + 20, height: bounds.height)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
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
