// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var released = true

    private func initWindowIfNeeded() {
        guard released else {
            return
        }

        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 850, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.delegate = self
        window.contentView = NSHostingView(rootView: Settings())

        window.title = LinearMouse.appName
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        window.center()

        self.window = window
        released = false
    }

    func bringToFront() {
        initWindowIfNeeded()

        guard let window else {
            return
        }

        window.bringToFront()
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        guard let window else {
            return
        }

        // It seems that if contentView is not manually unassigned,
        // Settings will not be recycled.
        window.contentView = nil

        // Mark self as released.
        released = true
    }
}
