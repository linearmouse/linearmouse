// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Foundation
import SwiftUI

class SettingsWindow: NSObject {
    static let shared = SettingsWindow()

    private var controller: NSWindowController?
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

        // This is the default value, just to make it explicit.
        // See https://github.com/linearmouse/linearmouse/issues/548
        window.isReleasedWhenClosed = true

        window.title = LinearMouse.appName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        window.contentView = NSHostingView(rootView: Settings())

        window.center()

        controller = .init(window: window)
        released = false
    }

    func bringToFront() {
        initWindowIfNeeded()
        controller?.window?.bringToFront()
    }
}

extension SettingsWindow: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        // It seems that if contentView is not manually unassigned,
        // Settings will not be recycled.
        controller?.window?.contentView = nil

        // Mark self as released.
        released = true
    }
}
