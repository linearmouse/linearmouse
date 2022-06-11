//
//  PreferencesWindow.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/12.
//

import Foundation
import SwiftUI

class PreferencesWindow: NSWindow {
    static var shared = PreferencesWindow()

    init() {
        super.init(
            contentRect: .init(x: 0, y: 0, width: 500, height: 600),
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
