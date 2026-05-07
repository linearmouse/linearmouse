// MIT License
// Copyright (c) 2021-2026 LinearMouse

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
    private var sessionActive = true
    private var sleeping = false

    func applicationDidFinishLaunching(_: Notification) {
        guard ProcessEnvironment.isRunningApp else {
            return
        }

        #if !DEBUG
            if AppMover.moveIfNecessary() {
                return
            }
        #endif

        guard AccessibilityPermission.enabled else {
            AccessibilityPermissionWindow.shared.bringToFront()
            return
        }

        setup()

        if CommandLine.arguments.contains("--show") {
            SettingsWindowController.shared.bringToFront()
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard ProcessEnvironment.isRunningApp else {
            return true
        }

        if flag {
            return true
        }

        SettingsWindowController.shared.bringToFront()

        return false
    }

    func applicationWillTerminate(_: Notification) {
        guard ProcessEnvironment.isRunningApp else {
            return
        }

        stop()
    }
}

extension AppDelegate {
    func setup() {
        setupConfiguration()
        setupNotifications()
        KeyboardSettingsSnapshot.shared.refresh()
        startIfAllowed()
    }

    func setupConfiguration() {
        ConfigurationState.shared.load()
        // Start watching the configuration file for hot reload
        ConfigurationState.shared.startHotReload()
    }

    func setupNotifications() {
        // Prepare user notifications for error popups
        Notifier.shared.setup()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("Session inactive", log: Self.log, type: .info)
            self?.sessionActive = false
            self?.stop()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("Session active", log: Self.log, type: .info)
            self?.sessionActive = true
            KeyboardSettingsSnapshot.shared.refresh()
            self?.startIfAllowed()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("System will sleep", log: Self.log, type: .info)
            self?.sleeping = true
            self?.stop()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("System did wake", log: Self.log, type: .info)
            self?.sleeping = false
            self?.restartIfAllowed()
            self?.requestLogitechControlsReconfigurationAfterWake()
        }
    }

    func startIfAllowed() {
        guard sessionActive, !sleeping else {
            return
        }

        start()
    }

    func restartIfAllowed() {
        stop()
        startIfAllowed()
    }

    func requestLogitechControlsReconfigurationAfterWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, sessionActive, !sleeping else {
                return
            }

            DeviceManager.shared.requestLogitechControlsForcedReconfiguration()
        }
    }

    func start() {
        DeviceManager.shared.start()
        BatteryDeviceMonitor.shared.enable()
        GlobalEventTap.shared.start()
    }

    func stop() {
        BatteryDeviceMonitor.shared.disable()
        DeviceManager.shared.stop()
        GlobalEventTap.shared.stop()
    }
}
