// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import SwiftUI

class PreferencesWindow: NSWindow {
    static var shared = PreferencesWindow()

    init() {
        super.init(
            contentRect: .init(x: 0, y: 0, width: 850, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false

        title = LinearMouse.appName

        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        contentView = NSHostingView(rootView: Preferences())

        center()
    }
}
