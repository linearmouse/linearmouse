//
//  AppDelegate.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/10.
//

import Combine
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = StatusItem()

    let cursorManager = CursorManager.shared

    var defaultsSubscription: AnyCancellable!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        withAccessibilityPermission {
            // register the start entry if the user grants the permission
            AutoStartManager.enable()

            // scrolling functionalities
            EventTap().enable()

            // subscribe to the user settings
            let defaults = AppDefaults.shared
            self.defaultsSubscription = defaults.objectWillChange.sink { _ in
                DispatchQueue.main.async {
                    self.update(defaults)
                }
            }
            self.update(defaults)
            self.cursorManager.start()
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

    func update(_ defaults: AppDefaults) {
        cursorManager.disableAccelerationAndSensitivity = defaults.linearMovementOn
        cursorManager.acceleration = defaults.cursorAcceleration
        cursorManager.sensitivity = defaults.cursorSensitivity
        cursorManager.update()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            return true
        }
        statusItem.openPreferencesAction()
        return false
    }
}
