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

/// Where each line of a text storage starts, kept up to date on every edit.
///
/// Lines end at LF only; the document converts every other line break when loading and pasting.
final class LineIndex {
    /// UTF-16 offsets of the line starts; the first line starts at 0.
    private var starts: [Int] = [0]
    private unowned let storage: NSTextStorage
    private var observer: NSObjectProtocol?

    init(storage: NSTextStorage) {
        self.storage = storage
        rebuild()
        observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil
        ) { [weak self] _ in
            self?.storageDidEdit()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var lineCount: Int { starts.count }

    /// 1-based number of the line containing the UTF-16 offset.
    func lineNumber(at offset: Int) -> Int {
        lastStart(atOrBefore: offset) + 1
    }

    /// UTF-16 offset where the 1-based line starts.
    func start(ofLine line: Int) -> Int {
        starts[(line - 1).clamped(to: 0...(starts.count - 1))]
    }

    private func storageDidEdit() {
        guard storage.editedMask.contains(.editedCharacters) else { return }
        let edited = storage.editedRange
        let delta = storage.changeInLength
        guard edited.location != NSNotFound else { return rebuild() }

        // Line starts behind a newline in the replaced text go; the ones after it move.
        let oldEnd = edited.upperBound - delta
        let low = firstStart(after: edited.location)
        let high = firstStart(after: oldEnd)
        starts.removeSubrange(low..<high)
        if delta != 0 {
            for index in low..<starts.count { starts[index] += delta }
        }
        starts.insert(contentsOf: newlineOffsets(in: edited).map { $0 + 1 }, at: low)
    }

    private func rebuild() {
        starts = [0] + newlineOffsets(in: NSRange(location: 0, length: storage.length)).map { $0 + 1 }
    }

    private func newlineOffsets(in range: NSRange) -> [Int] {
        let string = storage.string as NSString
        var offsets: [Int] = []
        var buffer = [unichar](repeating: 0, count: 4096)
        var location = range.location
        while location < range.upperBound {
            let length = min(buffer.count, range.upperBound - location)
            string.getCharacters(&buffer, range: NSRange(location: location, length: length))
            for index in 0..<length where buffer[index] == 0x0A {
                offsets.append(location + index)
            }
            location += length
        }
        return offsets
    }

    /// Index of the last line start at or before the offset.
    private func lastStart(atOrBefore offset: Int) -> Int {
        max(firstStart(after: offset) - 1, 0)
    }

    /// Index of the first line start greater than the offset.
    private func firstStart(after offset: Int) -> Int {
        var low = 0, high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= offset { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
