//
//  AccessibilityPermissionWindow.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/9.
//

import Foundation
import SwiftUI

class AccessibilityPermissionWindow: NSWindow {
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

        center()

        AccessibilityPermission.pollingUntilEnabled {
            self.close()
        }
    }
}

extension AccessibilityPermissionWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard AccessibilityPermission.enabled else {
            NSApp.terminate(nil)
            exit(0)
        }

        StatusItem.shared.openPreferences()
    }
}
