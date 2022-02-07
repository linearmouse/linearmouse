//
//  PreferencesWindow.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/12.
//

import Foundation
import SwiftUI

extension NSToolbar.Identifier {
    static let main = NSToolbar.Identifier("MainToolbar")
}

extension NSToolbarItem.Identifier {
    static let general = NSToolbarItem.Identifier("general")
    static let cursor = NSToolbarItem.Identifier("cursor")
}

class PreferencesWindow: NSWindow {
    init() {
        super.init(
            contentRect: .init(x: 0, y: 0, width: 500, height: 550),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false

        title = String(format: NSLocalizedString("%@ Preferences", comment: ""), LinearMouse.appName)

        contentView = NSHostingView(rootView: PreferencesView())

        center()
    }
}
