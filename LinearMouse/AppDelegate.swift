//
//  AppDelegate.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/10.
//

import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuIcon")
        }

        let menu = NSMenu()
        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "")
        menu.addItem(quitMenuItem)
        statusItem.menu = menu

        acquirePrivileges {
            // register the start entry if the user grants the permission
            AutoStartManager.enable()

            // the core functionality
            ScrollWheelEventTap().enable()
        }
    }

    func acquirePrivileges(shouldAskForPermission: Bool = true, completion: @escaping () -> Void) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): shouldAskForPermission] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.acquirePrivileges(shouldAskForPermission: false, completion: completion)
            }
            return
        }
        completion()
    }

    @objc func quit() {
        // remove the start entry if the user quits LinearMouse manually
        AutoStartManager.disable()

        NSApp.terminate(self)
    }
}
