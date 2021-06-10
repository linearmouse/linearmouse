//
//  AppDelegate.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/10.
//

import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    static let mouseScrollLines = Int64(3)

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    let scrollEventCallback: CGEventTapCallBack = { (proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon) in
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        // trackpad events are continuous and we simply ignore them
        if isContinuous == 0 {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: event.getIntegerValueField(.scrollWheelEventDeltaAxis1).signum() * mouseScrollLines)
        }
        return Unmanaged.passUnretained(event)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuIcon")
        }

        let menu = NSMenu()
        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "")
        menu.addItem(quitMenuItem)
        statusItem.menu = menu

        acquirePrivileges { self.startup() }
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

    func startup() {
        let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: scrollEventCallback,
            userInfo: nil
        )
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: eventTap!, enable: true)
        CFRunLoopRun()
    }

    @objc func quit() {
        NSApp.terminate(self)
    }
}
