//
//  PreferencesWindow.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/12.
//

import Foundation
import SwiftUI

class PreferencesWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false)

        isReleasedWhenClosed = false

        title = "\(LinearMouse.appName) Preferences"

        contentView = NSHostingView(rootView: PreferencesView())

        center()
    }
}
