// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import AppMover
import Combine
import LaunchAtLogin
import os.log
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

    private let autoUpdateManager = AutoUpdateManager.shared
    private let statusItem = StatusItem.shared
    private var subscriptions = Set<AnyCancellable>()
    private var eventTap: EventTap?

    override init() {
        LaunchAtLogin.migrateIfNeeded()
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard ProcessEnvironment.isRunningApp else { return }

        #if RELEASE
            AppMover.moveIfNecessary()
        #endif

        guard AccessibilityPermission.enabled else {
            AccessibilityPermissionWindow.shared.bringToFront()
            return
        }

        setup()

        if CommandLine.arguments.contains("--show") {
            SettingsWindow.shared.bringToFront()
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard ProcessEnvironment.isRunningApp else { return true }

        if flag {
            return true
        }

        SettingsWindow.shared.bringToFront()

        return false
    }

    func applicationWillTerminate(_: Notification) {
        guard ProcessEnvironment.isRunningApp else { return }

        stop()
    }
}

extension AppDelegate {
    func setup() {
        setupConfiguration()
        setupNotifications()
        start()
    }

    func setupConfiguration() {
        ConfigurationState.shared.load()
    }

    func setupNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                os_log("Session inactive", log: Self.log, type: .debug)
                self?.stop()
            }
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                os_log("Session active", log: Self.log, type: .debug)
                self?.start()
            }
        )
    }

    func start() {
        DeviceManager.shared.start()
        EventTap.shared.start()
    }

    func stop() {
        DeviceManager.shared.stop()
        EventTap.shared.stop()
    }
}
