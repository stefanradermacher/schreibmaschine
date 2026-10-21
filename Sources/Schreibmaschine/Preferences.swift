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

/// Keys and defaults of the settings in UserDefaults.
///
/// Showing line numbers, wrapping and invisibles are defaults for new windows; each window can
/// switch them in the View menu. Font, indentation and highlighting apply to all windows at once.
enum Preferences {
    static let fontName = "fontName"                        // empty: the system's monospaced font
    static let fontSize = "fontSize"
    static let showsLineNumbers = "showsLineNumbers"
    static let wrapsLines = "wrapsLines"
    static let showsInvisibles = "showsInvisibles"
    static let highlightsCurrentLine = "highlightsCurrentLine"
    static let highlightsSyntax = "highlightsSyntax"
    static let showsDocumentList = "showsDocumentList"
    static let tabWidth = "tabWidth"
    static let lineHeight = "lineHeight"
    static let wrapColumn = "wrapColumn"
    static let indentsWithSpaces = "indentsWithSpaces"
    static let autoIndents = "autoIndents"
    static let defaultEncoding = "defaultEncoding"          // String.Encoding.rawValue
    static let writesUTF8BOM = "writesUTF8BOM"
    static let defaultLineEnding = "defaultLineEnding"      // LineEnding.rawValue
    static let opensDocumentsInTabs = "opensDocumentsInTabs"
    static let startupAction = "startupAction"              // StartupAction.rawValue
    static let searchCaseSensitive = "searchCaseSensitive"
    static let searchWholeWords = "searchWholeWords"
    static let searchRegularExpression = "searchRegularExpression"
    static let searchHistory = "searchHistory"
    static let windowWidth = "windowWidth"
    static let windowHeight = "windowHeight"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            fontName: "",
            fontSize: 13.0,
            showsLineNumbers: true,
            wrapsLines: true,
            showsInvisibles: false,
            highlightsCurrentLine: true,
            highlightsSyntax: true,
            showsDocumentList: false,
            tabWidth: 4,
            lineHeight: 1.2,
            wrapColumn: 80,
            indentsWithSpaces: true,
            autoIndents: true,
            defaultEncoding: Int(String.Encoding.utf8.rawValue),
            writesUTF8BOM: false,
            defaultLineEnding: LineEnding.lf.rawValue,
            opensDocumentsInTabs: true,
            startupAction: StartupAction.restoreSession.rawValue,
        ])
    }

    private static var defaults: UserDefaults { .standard }

    static var font: NSFont {
        let size = CGFloat(defaults.double(forKey: fontSize)).clamped(to: 6...72)
        if let name = defaults.string(forKey: fontName), !name.isEmpty, let font = NSFont(name: name, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func setFont(_ font: NSFont) {
        let system = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        defaults.set(font.fontName == system.fontName ? "" : font.fontName, forKey: fontName)
        defaults.set(Double(font.pointSize), forKey: fontSize)
    }

    static var tabWidthValue: Int { defaults.integer(forKey: tabWidth).clamped(to: 1...16) }
    /// Line height as a multiple of what the font needs, in steps of 0.1.
    static var lineHeightValue: Double { (defaults.double(forKey: lineHeight) * 10).rounded().clamped(to: 10...20) / 10 }
    static var wrapColumnValue: Int { defaults.integer(forKey: wrapColumn).clamped(to: 10...1000) }
    static var indentsWithSpacesValue: Bool { defaults.bool(forKey: indentsWithSpaces) }
    static var autoIndentsValue: Bool { defaults.bool(forKey: autoIndents) }
    static var highlightsCurrentLineValue: Bool { defaults.bool(forKey: highlightsCurrentLine) }
    static var highlightsSyntaxValue: Bool { defaults.bool(forKey: highlightsSyntax) }

    static var defaultEncodingValue: String.Encoding {
        let raw = UInt(defaults.integer(forKey: defaultEncoding))
        let encoding = String.Encoding(rawValue: raw)
        return TextEncoding.all.contains(encoding) ? encoding : .utf8
    }

    static var startupActionValue: StartupAction {
        StartupAction(rawValue: defaults.string(forKey: startupAction) ?? "") ?? .restoreSession
    }

    static var defaultLineEndingValue: LineEnding {
        LineEnding(rawValue: defaults.string(forKey: defaultLineEnding) ?? "") ?? .lf
    }
}

/// What the app opens when it is started without a file.
enum StartupAction: String, CaseIterable {
    case restoreSession, newDocument, nothing
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
