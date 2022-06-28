// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import os.log
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

    private let autoUpdateManager = AutoUpdateManager.shared
    private let statusItem = StatusItem.shared
    private var subscriptions = Set<AnyCancellable>()
    private var eventTap: EventTap?

    func applicationDidFinishLaunching(_: Notification) {
        guard ProcessEnvironment.isRunningApp else { return }

        if !AccessibilityPermission.enabled {
            AccessibilityPermissionWindow.shared.bringToFront()
        }

        AccessibilityPermission.pollingUntilEnabled(completion: setup)
    }

    func setup() {
        ConfigurationState.shared.$activeScheme.sink { _ in
            // TODO: Apply settings
        }
        .store(in: &subscriptions)

        // register the start entry if the user grants the permission
        AutoStartManager.enable()

        // scrolling functionalities
        let eventTap = EventTap()
        eventTap.enable()
        self.eventTap = eventTap

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main,
            using: { _ in
                os_log("Session inactive", log: Self.log, type: .debug)
                if let eventTap = self.eventTap {
                    eventTap.disable()
                }
                DeviceManager.shared.pause()
            }
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main,
            using: { _ in
                os_log("Session active", log: Self.log, type: .debug)
                if let eventTap = self.eventTap {
                    eventTap.enable()
                }
                DeviceManager.shared.resume()
            }
        )
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard ProcessEnvironment.isRunningApp else { return true }

        if flag {
            return true
        }

        PreferencesWindow.shared.bringToFront()

        return false
    }

    func applicationWillTerminate(_: Notification) {
        guard ProcessEnvironment.isRunningApp else { return }

        DeviceManager.shared.pause()
    }
}
