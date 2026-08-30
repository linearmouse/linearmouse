// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppMover
import Combine
import LaunchAtLogin
import os.log
import SwiftUI

struct AppLifecycleAdmission {
    var sessionActive = true
    var sleeping = false
    var terminationCleanupStarted = false

    var allowsStart: Bool {
        sessionActive && !sleeping && !terminationCleanupStarted
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

    private let autoUpdateManager = AutoUpdateManager.shared
    private let statusItem = StatusItem.shared
    private var subscriptions = Set<AnyCancellable>()
    private var lifecycleAdmission = AppLifecycleAdmission()

    /// Runs the one-time legacy -> SMAppService login-item migration on launch.
    ///
    /// It's a no-op below macOS 13 and after the first successful run. This call
    /// was lost in 5437d88 and is restored here (issue #1328).
    override init() {
        LaunchAtLogin.migrateIfNeeded()
    }

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ProcessEnvironment.isRunningApp else {
            return .terminateNow
        }

        guard !lifecycleAdmission.terminationCleanupStarted else {
            return .terminateLater
        }
        lifecycleAdmission.terminationCleanupStarted = true

        stop(restoringHighResolutionWheel: true) { [weak sender] in
            sender?.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
            self?.lifecycleAdmission.sessionActive = false
            self?.stop(restoringHighResolutionWheel: true)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("Session active", log: Self.log, type: .info)
            self?.lifecycleAdmission.sessionActive = true
            KeyboardSettingsSnapshot.shared.refresh()
            self?.restartIfAllowed()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("System will sleep", log: Self.log, type: .info)
            self?.lifecycleAdmission.sleeping = true
            self?.stopForSleep()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("System did wake", log: Self.log, type: .info)
            self?.lifecycleAdmission.sleeping = false
            self?.completeSleepStopAndRestartIfAllowed()
        }
    }

    func startIfAllowed() {
        guard lifecycleAdmission.allowsStart else {
            return
        }

        start()
    }

    func restartIfAllowed() {
        stop { [weak self] in
            self?.startIfAllowed()
        }
    }

    /// A wake resumes the sleep teardown already in flight; it must not
    /// upgrade that teardown to terminal hardware restoration and delay the
    /// new observation lifetime while the receiver is still coming online.
    func completeSleepStopAndRestartIfAllowed() {
        stopForSleep { [weak self] in
            guard let self else {
                return
            }
            startIfAllowed()
            requestLogitechReceiverRediscoveryAfterWake()
        }
    }

    func requestLogitechReceiverRediscoveryAfterWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.lifecycleAdmission.allowsStart else {
                return
            }

            DeviceManager.shared.requestLogitechReceiverRediscovery()
        }
    }

    func start() {
        DeviceManager.shared.start()
        BatteryDeviceMonitor.shared.enable()
        GlobalEventTap.shared.start()
    }

    func stop(
        restoringHighResolutionWheel: Bool = true,
        applyingSleepHiResPolicy: Bool = false,
        controlsTeardownPolicy: DeviceManagerControlsTeardownPolicy = .restore,
        completion: (() -> Void)? = nil
    ) {
        BatteryDeviceMonitor.shared.disable()
        DeviceManager.shared.stop(
            restoringHighResolutionWheel: restoringHighResolutionWheel,
            applyingSleepHiResPolicy: applyingSleepHiResPolicy,
            controlsTeardownPolicy: controlsTeardownPolicy,
            completion: completion
        )
        GlobalEventTap.shared.stop()
    }

    private func stopForSleep(completion: (() -> Void)? = nil) {
        stop(
            restoringHighResolutionWheel: false,
            applyingSleepHiResPolicy: true,
            controlsTeardownPolicy: .sleepPreserve,
            completion: completion
        )
    }
}
