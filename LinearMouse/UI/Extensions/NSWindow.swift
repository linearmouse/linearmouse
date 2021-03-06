// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

extension NSWindow {
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
