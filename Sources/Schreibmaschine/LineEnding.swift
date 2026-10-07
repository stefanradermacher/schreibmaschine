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

/// Line endings of a file. In the editor every line ends with LF; the file's own line ending
/// is restored when saving.
enum LineEnding: String, CaseIterable {
    case lf, crlf, cr

    var separator: String {
        switch self {
        case .lf: "\n"
        case .crlf: "\r\n"
        case .cr: "\r"
        }
    }

    /// Short name for the status bar.
    var shortName: String {
        switch self {
        case .lf: "LF"
        case .crlf: "CRLF"
        case .cr: "CR"
        }
    }

    /// Name for menus.
    var name: String {
        switch self {
        case .lf: String(localized: "LF (macOS, Linux)")
        case .crlf: String(localized: "CRLF (Windows)")
        case .cr: String(localized: "CR (klassisches Mac OS)")
        }
    }

    /// The prevailing line ending of a text, and whether it uses more than one kind.
    /// A text without line breaks has none.
    static func detect(in text: String) -> (ending: LineEnding?, isMixed: Bool) {
        var lf = 0, crlf = 0, cr = 0
        var previousWasCR = false
        for unit in text.utf16 {
            switch unit {
            case 0x0A:
                if previousWasCR { crlf += 1; cr -= 1 } else { lf += 1 }
                previousWasCR = false
            case 0x0D:
                cr += 1
                previousWasCR = true
            default:
                previousWasCR = false
            }
        }
        let counts: [(LineEnding, Int)] = [(.lf, lf), (.crlf, crlf), (.cr, cr)]
        let used = counts.filter { $0.1 > 0 }
        guard let prevailing = used.max(by: { $0.1 < $1.1 }) else { return (nil, false) }
        return (prevailing.0, used.count > 1)
    }
}

extension String {
    /// The text with every CRLF and CR replaced by LF.
    var normalizingLineEndings: String {
        // Not contains("\r"): Swift treats CRLF as a single Character and would not find it.
        guard utf16.contains(0x0D) else { return self }
        return replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
