import Foundation

/// Compares two texts line by line, with the difference algorithm of the Swift standard library
/// (Myers), and within changed lines character by character.
struct TextDiff {
    struct Options: Equatable {
        var ignoresWhitespace = false
        var ignoresCase = false
    }

    /// A run of lines that differs: `left` lines on the left were replaced by `right` lines on
    /// the right. Either range may be empty (insertion or deletion). Lines count from 0.
    struct Hunk: Equatable {
        var left: Range<Int>
        var right: Range<Int>

        var kind: Kind {
            if left.isEmpty { return .inserted }
            if right.isEmpty { return .deleted }
            return .changed
        }

        enum Kind { case inserted, deleted, changed }
    }

    let hunks: [Hunk]
    /// Characters that differ within changed lines, as UTF-16 ranges in each whole text.
    let leftCharacters: [NSRange]
    let rightCharacters: [NSRange]

    /// Without `characters`, only lines are compared, as for the marks in the ruler.
    init(left: String, right: String, options: Options, characters: Bool = true) {
        let leftLines = Self.lines(of: left)
        let rightLines = Self.lines(of: right)
        let leftKeys = leftLines.map { Self.key($0.text, options) }
        let rightKeys = rightLines.map { Self.key($0.text, options) }

        let difference = rightKeys.difference(from: leftKeys)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        // Walk both texts side by side; removed and inserted lines that meet form a hunk.
        var hunks: [Hunk] = []
        var i = 0, j = 0
        while i < leftLines.count || j < rightLines.count {
            if i < leftLines.count, j < rightLines.count, !removed.contains(i), !inserted.contains(j) {
                i += 1; j += 1
                continue
            }
            let startLeft = i, startRight = j
            while i < leftLines.count, removed.contains(i) { i += 1 }
            while j < rightLines.count, inserted.contains(j) { j += 1 }
            if startLeft == i, startRight == j {
                // Only possible at the end of one side; take the rest as a hunk.
                i = leftLines.count; j = rightLines.count
            }
            hunks.append(Hunk(left: startLeft..<i, right: startRight..<j))
        }
        self.hunks = hunks

        // Within changed hunks the lines are paired in order and compared character by character.
        var leftCharacters: [NSRange] = [], rightCharacters: [NSRange] = []
        for hunk in hunks where characters && hunk.kind == .changed {
            for (a, b) in zip(hunk.left, hunk.right) {
                let (l, r) = Self.characterDifferences(leftLines[a], rightLines[b])
                leftCharacters += l
                rightCharacters += r
            }
        }
        self.leftCharacters = leftCharacters
        self.rightCharacters = rightCharacters
    }

    struct Line {
        let text: String
        /// UTF-16 offset of the line in the whole text.
        let start: Int
    }

    static func lines(of text: String) -> [Line] {
        var lines: [Line] = []
        let string = text as NSString
        var start = 0
        while start < string.length {
            let range = string.lineRange(for: NSRange(location: start, length: 0))
            var content = range
            if content.length > 0, string.character(at: content.upperBound - 1) == 0x0A { content.length -= 1 }
            lines.append(Line(text: string.substring(with: content), start: range.location))
            start = range.upperBound
        }
        return lines
    }

    private static func key(_ line: String, _ options: Options) -> String {
        var key = line
        if options.ignoresWhitespace { key = key.filter { !$0.isWhitespace } }
        if options.ignoresCase { key = key.lowercased() }
        return key
    }

    /// The characters that differ between two lines, as ranges in the whole texts. Very long
    /// lines are marked as a whole, the character comparison would take too long.
    private static func characterDifferences(_ left: Line, _ right: Line) -> ([NSRange], [NSRange]) {
        let a = Array(left.text.utf16), b = Array(right.text.utf16)
        guard a.count < 5_000, b.count < 5_000 else {
            return ([NSRange(location: left.start, length: a.count)], [NSRange(location: right.start, length: b.count)])
        }
        let difference = b.difference(from: a)
        var removed: [Int] = [], inserted: [Int] = []
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.append(offset)
            case .insert(let offset, _, _): inserted.append(offset)
            }
        }
        return (ranges(removed.sorted(), base: left.start), ranges(inserted.sorted(), base: right.start))
    }

    /// Runs of neighbouring offsets as ranges.
    private static func ranges(_ offsets: [Int], base: Int) -> [NSRange] {
        var result: [NSRange] = []
        for offset in offsets {
            if let last = result.last, last.upperBound == base + offset {
                result[result.count - 1].length += 1
            } else {
                result.append(NSRange(location: base + offset, length: 1))
            }
        }
        return result
    }

    /// The hunks as a unified diff, the way `diff -u` writes it, with three lines of context.
    static func unified(left: String, right: String, leftName: String, rightName: String, hunks: [Hunk]) -> String {
        let a = lines(of: left).map(\.text), b = lines(of: right).map(\.text)
        var output = "--- \(leftName)\n+++ \(rightName)\n"
        var index = 0
        while index < hunks.count {
            // Hunks closer than twice the context go into one block.
            var end = index
            while end + 1 < hunks.count, hunks[end + 1].left.lowerBound - hunks[end].left.upperBound <= 6 { end += 1 }
            let first = hunks[index], last = hunks[end]
            let leftStart = max(first.left.lowerBound - 3, 0), rightStart = max(first.right.lowerBound - 3, 0)
            let leftEnd = min(last.left.upperBound + 3, a.count), rightEnd = min(last.right.upperBound + 3, b.count)
            output += "@@ -\(leftStart + 1),\(leftEnd - leftStart) +\(rightStart + 1),\(rightEnd - rightStart) @@\n"
            var i = leftStart, j = rightStart
            for hunk in hunks[index...end] {
                while i < hunk.left.lowerBound { output += " " + a[i] + "\n"; i += 1; j += 1 }
                for k in hunk.left { output += "-" + a[k] + "\n" }
                for k in hunk.right { output += "+" + b[k] + "\n" }
                i = hunk.left.upperBound; j = hunk.right.upperBound
            }
            while i < leftEnd { output += " " + a[i] + "\n"; i += 1; j += 1 }
            index = end + 1
        }
        return output
    }
}
