// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

extension NSWindow {
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
