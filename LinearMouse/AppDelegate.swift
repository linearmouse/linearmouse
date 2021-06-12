//
//  AppDelegate.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/10.
//

import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = StatusItem()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        withAccessibilityPermission {
            // register the start entry if the user grants the permission
            AutoStartManager.enable()

            // the core functionality
            ScrollWheelEventTap().enable()
        }
    }

    func withAccessibilityPermission(shouldAskForPermission: Bool = true, completion: @escaping () -> Void) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): shouldAskForPermission] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.withAccessibilityPermission(shouldAskForPermission: false, completion: completion)
            }
            return
        }
        completion()
    }
}
