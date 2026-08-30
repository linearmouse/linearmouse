// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppMover
import Combine
import LaunchAtLogin
import os.log
import SwiftUI

struct AppLifecycleAdmission {
    enum Target: Equatable {
        case running
        case suspended
        case stopped
    }

    var sessionActive = true
    var sleeping = false
    var terminationCleanupStarted = false

    var target: Target {
        if terminationCleanupStarted || !sessionActive {
            return .stopped
        }
        return sleeping ? .suspended : .running
    }

    var allowsStart: Bool {
        target == .running
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

    private let autoUpdateManager = AutoUpdateManager.shared
    private let statusItem = StatusItem.shared
    private var subscriptions = Set<AnyCancellable>()
    private var lifecycleAdmission = AppLifecycleAdmission()
    private var lifecycleReady = false
    private var workspaceNotificationObservers = [NSObjectProtocol]()
    private var terminationRequest: BoundedCleanupRequest?

    /// Runs the one-time legacy -> SMAppService login-item migration on launch.
    ///
    /// It's a no-op below macOS 13 and after the first successful run. This call
    /// was lost in 5437d88 and is restored here (issue #1328).
    override init() {
        LaunchAtLogin.migrateIfNeeded()
    }

    func applicationWillFinishLaunching(_: Notification) {
        guard ProcessEnvironment.isRunningApp else {
            return
        }

        setupNotifications()
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

        guard terminationRequest == nil else {
            return .terminateLater
        }
        lifecycleAdmission.terminationCleanupStarted = true

        let request = BoundedCleanupRequest(
            onTimeout: {
                os_log(
                    "Timed out waiting for application termination cleanup",
                    log: Self.log,
                    type: .error
                )
            },
            completion: { _ in
                sender.reply(toApplicationShouldTerminate: true)
            }
        )
        terminationRequest = request

        stop {
            request.complete()
        }
        return .terminateLater
    }
}

extension AppDelegate {
    func setup() {
        setupConfiguration()
        setupNotifications()
        KeyboardSettingsSnapshot.shared.refresh()
        lifecycleReady = true
        startIfAllowed()
    }

    func setupConfiguration() {
        ConfigurationState.shared.load()
        // Start watching the configuration file for hot reload
        ConfigurationState.shared.startHotReload()
    }

    func setupNotifications() {
        guard workspaceNotificationObservers.isEmpty else {
            return
        }

        // Prepare user notifications for error popups
        Notifier.shared.setup()
        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceNotificationObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("Session inactive", log: Self.log, type: .info)
            self?.lifecycleAdmission.sessionActive = false
            self?.reconcileLifecycle()
        })

        workspaceNotificationObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("Session active", log: Self.log, type: .info)
            self?.lifecycleAdmission.sessionActive = true
            KeyboardSettingsSnapshot.shared.refresh()
            self?.reconcileLifecycle()
        })

        workspaceNotificationObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("System will sleep", log: Self.log, type: .info)
            self?.lifecycleAdmission.sleeping = true
            self?.reconcileLifecycle()
        })

        workspaceNotificationObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("System did wake", log: Self.log, type: .info)
            self?.lifecycleAdmission.sleeping = false
            self?.reconcileLifecycle()
        })
    }

    func startIfAllowed() {
        guard lifecycleAdmission.allowsStart else {
            return
        }

        activateRunningLifecycle()
    }

    func reconcileLifecycle() {
        guard lifecycleReady else {
            return
        }

        switch lifecycleAdmission.target {
        case .running:
            activateRunningLifecycle()
        case .suspended:
            BatteryDeviceMonitor.shared.disable()
            GlobalEventTap.shared.stop()
            DeviceManager.shared.suspendForSleep()
        case .stopped:
            stop()
        }
    }

    private func activateRunningLifecycle() {
        DeviceManager.shared.resumeFromSleep { [weak self] in
            guard let self, self.lifecycleAdmission.target == .running else {
                self?.reconcileLifecycle()
                return
            }

            start()
        }
    }

    func start() {
        DeviceManager.shared.start()
        BatteryDeviceMonitor.shared.enable()
        GlobalEventTap.shared.start()
    }

    func stop(
        logitechTeardownPolicy: DeviceManagerLogitechTeardownPolicy = .restore,
        completion: (() -> Void)? = nil
    ) {
        BatteryDeviceMonitor.shared.disable()
        GlobalEventTap.shared.stop()
        DeviceManager.shared.stop(
            logitechTeardownPolicy: logitechTeardownPolicy,
            completion: completion
        )
    }
}
