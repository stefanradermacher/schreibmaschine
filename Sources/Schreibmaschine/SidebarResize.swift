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

/// The edge of a sidebar, to drag it wider or narrower as in the Finder. It lies over the line
/// between sidebar and text, a few points to either side. The width is kept in the settings,
/// for every window, once the mouse is released.
final class SidebarResizeHandle: NSView {
    static let minimumWidth: CGFloat = 140
    /// The text keeps at least the rest of the window.
    static let maximumShare: CGFloat = 0.4

    private let width: NSLayoutConstraint
    private let key: String
    /// A sidebar on the right grows when its edge is dragged to the left.
    private let growsLeftward: Bool
    private var startX: CGFloat = 0
    private var startWidth: CGFloat = 0

    init(width: NSLayoutConstraint, key: String, growsLeftward: Bool = false) {
        self.width = width
        self.key = key
        self.growsLeftward = growsLeftward
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .columnResize)
    }

    override func mouseDown(with event: NSEvent) {
        startX = event.locationInWindow.x
        startWidth = width.constant
    }

    override func mouseDragged(with event: NSEvent) {
        let available = superview?.bounds.width ?? .greatestFiniteMagnitude
        let moved = event.locationInWindow.x - startX
        let proposed = startWidth + (growsLeftward ? -moved : moved)
        width.constant = proposed.clamped(to: Self.minimumWidth...max(Self.minimumWidth, available * Self.maximumShare)).rounded()
    }

    override func mouseUp(with event: NSEvent) {
        if width.constant != startWidth { UserDefaults.standard.set(Double(width.constant), forKey: key) }
    }

    /// The width a sidebar has from the settings, within the limits.
    static func storedWidth(_ key: String) -> CGFloat {
        max(CGFloat(UserDefaults.standard.double(forKey: key)), minimumWidth)
    }
}
