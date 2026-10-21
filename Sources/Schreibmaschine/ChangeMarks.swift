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

/// How the ruler marks the lines that differ from the saved file.
enum ChangeMarkStyle: String, CaseIterable {
    /// No marks.
    case off
    /// New and changed lines alike in the app's steel blue, as Xcode marks them.
    case single
    /// As in the comparison: new lines blue, changed lines red.
    case compare
    /// New lines green, changed lines blue, as in Visual Studio Code.
    case colorful

    static var current: ChangeMarkStyle {
        ChangeMarkStyle(rawValue: UserDefaults.standard.string(forKey: Preferences.changeMarks) ?? "") ?? .single
    }

    var title: String {
        switch self {
        case .off: String(localized: "Aus")
        case .single: String(localized: "Einfarbig")
        case .compare: String(localized: "Wie im Vergleich: neu blau, geändert rot")
        case .colorful: String(localized: "Neu grün, geändert blau")
        }
    }

    private static let steelBlue = NSColor(named: "AccentColor") ?? .controlAccentColor

    var addedColor: NSColor {
        switch self {
        case .off, .single: Self.steelBlue
        case .compare: .systemBlue
        case .colorful: .systemGreen
        }
    }

    var changedColor: NSColor {
        switch self {
        case .off, .single: Self.steelBlue
        case .compare: .systemRed
        case .colorful: .systemBlue
        }
    }

    var deletedColor: NSColor {
        self == .single || self == .off ? Self.steelBlue : .systemRed
    }
}

/// The lines of a document that differ from the saved file, numbered from 1.
struct LineChanges: Equatable {
    var added = IndexSet()
    var changed = IndexSet()
    /// Lines above which saved lines are missing; one past the last line for the end.
    var deletedBefore = IndexSet()

    /// Above this many lines the marks stay off, so that typing in very long files is not
    /// slowed down.
    static let lineLimit = 200_000

    init() {}

    init(saved: String, current: String) {
        let diff = TextDiff(left: saved, right: current, options: TextDiff.Options(), characters: false)
        for hunk in diff.hunks {
            let lines = IndexSet(integersIn: (hunk.right.lowerBound + 1)..<(hunk.right.upperBound + 1))
            switch hunk.kind {
            case .inserted: added.formUnion(lines)
            case .changed: changed.formUnion(lines)
            case .deleted: deletedBefore.insert(hunk.right.lowerBound + 1)
            }
        }
    }
}

extension TextDocument {
    /// Posted when the marks of changed lines are new.
    static let lineChangesDidChange = Notification.Name("TextDocumentLineChangesDidChange")

    /// Compares the text with the saved one a moment after the last edit, away from the main
    /// thread. Documents without a file have nothing to compare with.
    func scheduleLineChanges() {
        lineChangesWork?.cancel()
        lineChangesGeneration += 1
        let generation = lineChangesGeneration
        guard ChangeMarkStyle.current != .off, let saved = savedText, lineIndex.lineCount <= LineChanges.lineLimit else {
            setLineChanges(nil)
            return
        }
        // The text is copied only once typing pauses, then compared in the background.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let current = textStorage.string
            DispatchQueue.global(qos: .utility).async {
                let changes = current == saved ? LineChanges() : LineChanges(saved: saved, current: current)
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.lineChangesGeneration else { return }
                    setLineChanges(changes)
                }
            }
        }
        lineChangesWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func setLineChanges(_ changes: LineChanges?) {
        guard changes != lineChanges else { return }
        lineChanges = changes
        NotificationCenter.default.post(name: Self.lineChangesDidChange, object: self)
    }
}
