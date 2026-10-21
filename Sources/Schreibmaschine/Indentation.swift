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

import Foundation

/// How a document indents: with spaces or tabs, and how wide one level is.
struct Indentation: Equatable, Codable {
    var width: Int
    var usesSpaces: Bool

    /// One level of indentation as text.
    var unit: String { usesSpaces ? String(repeating: " ", count: width) : "\t" }

    static var preferred: Indentation {
        Indentation(width: Preferences.tabWidthValue, usesSpaces: Preferences.indentsWithSpacesValue)
    }

    /// The indentation a text already uses, from its first few thousand lines: tabs if most
    /// indented lines start with a tab, otherwise the most common step between the indentation
    /// of neighbouring lines. nil if the text is not indented.
    static func detect(in text: String, fallbackWidth: Int) -> Indentation? {
        var tabLines = 0, spaceLines = 0
        var steps: [Int: Int] = [:]
        var previous = 0
        // Only the first lines are split off; the rest stays one piece, however long the text.
        for line in text.split(separator: "\n", maxSplits: 5000, omittingEmptySubsequences: true).prefix(5000) {
            guard line.contains(where: { !$0.isWhitespace }) else { continue }
            if line.hasPrefix("\t") {
                tabLines += 1
                continue
            }
            let spaces = line.prefix { $0 == " " }.count
            // " * " continues a block comment and says nothing about the indentation.
            let rest = line.dropFirst(spaces)
            if rest.hasPrefix("*") { continue }
            if spaces > 0 { spaceLines += 1 }
            let step = abs(spaces - previous)
            if step >= 2 && step <= 8 { steps[step, default: 0] += 1 }
            previous = spaces
        }
        if tabLines == 0 && spaceLines == 0 { return nil }
        if tabLines > spaceLines { return Indentation(width: fallbackWidth, usesSpaces: false) }
        // On a tie the order decides: 2 before 4 before 3 before 8.
        let width = [2, 4, 3, 8].max { (steps[$0] ?? 0) < (steps[$1] ?? 0) } ?? fallbackWidth
        return Indentation(width: (steps[width] ?? 0) > 0 ? width : fallbackWidth, usesSpaces: true)
    }
}
