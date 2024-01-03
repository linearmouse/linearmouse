// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Foundation
import SwiftUI

class AccessibilityPermissionWindow: NSWindow {
    static let shared = AccessibilityPermissionWindow()

    init() {
        super.init(
            contentRect: .init(x: 0, y: 0, width: 450, height: 200),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        delegate = self

        isReleasedWhenClosed = true

        contentView = NSHostingView(rootView: AccessibilityPermissionView())

        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        level = .floating

        center()

        AccessibilityPermission.pollingUntilEnabled {
            self.close()
        }
    }

    func moveAside() {
        if let screenFrame = screen?.visibleFrame {
            let origin = CGPoint(x: screenFrame.maxX - frame.width, y: frame.minY)
            setFrame(.init(origin: origin, size: frame.size), display: true, animate: true)
        }
    }
}

extension AccessibilityPermissionWindow: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        guard AccessibilityPermission.enabled else {
            NSApp.terminate(nil)
            exit(0)
        }

        Application.restart()
    }
}
