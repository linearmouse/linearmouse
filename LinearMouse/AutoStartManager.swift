//
//  AutoStartManager.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/11.
//

import Foundation
import LoginServiceKit
import LaunchAtLogin

class AutoStartManager {
    static func enable() {
        // LoginServiceKit uses some deprecated APIs that
        // are not functional in macOS Ventura 13.0.
        //
        // I use LaunchAtLogin as an alterative. However,
        // the login items added by LoginServiceKit should
        // be removed, too. So I'll keep the line below
        // for several releases.
        LoginServiceKit.removeLoginItems()
        LaunchAtLogin.isEnabled = true
    }

    static func disable() {
        LoginServiceKit.removeLoginItems()
        LaunchAtLogin.isEnabled = false
    }
}
