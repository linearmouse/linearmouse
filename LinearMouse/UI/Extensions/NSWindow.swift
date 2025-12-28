// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

extension NSWindow {
    func bringToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
