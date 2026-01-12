// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension NSWindow {
    func bringToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
