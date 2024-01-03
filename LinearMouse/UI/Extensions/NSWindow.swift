// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

extension NSWindow {
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
