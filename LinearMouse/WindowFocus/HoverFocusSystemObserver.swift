// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit

/// Observes on the main run loop. The Dock exposes Mission Control transitions
/// through AX notifications, including trackpad gestures (which need no keys).
final class HoverFocusSystemObserver {
    private let changed: (Bool?) -> Void
    private var tokens: [NSObjectProtocol] = []
    private var dockObserver: AXObserver?
    private var dock: AXUIElement?
    private var missionControl = false
    private var suspension = HoverFocusSuspension()
    private let notifications = [
        "AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop", "AXExposeExit"
    ]

    init(changed: @escaping (Bool?) -> Void) {
        self.changed = changed
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.changed(nil)
            })
        }
        let suspensionNotifications: [(Notification.Name, WritableKeyPath<HoverFocusSuspension, Bool>, Bool)] = [
            (NSWorkspace.sessionDidResignActiveNotification, \.sessionInactive, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, \.sessionInactive, false),
            (NSWorkspace.willSleepNotification, \.sleeping, true),
            (NSWorkspace.didWakeNotification, \.sleeping, false),
            (NSWorkspace.screensDidSleepNotification, \.screensSleeping, true),
            (NSWorkspace.screensDidWakeNotification, \.screensSleeping, false)
        ]
        for (name, reason, suspended) in suspensionNotifications {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else {
                    return
                }
                suspension[keyPath: reason] = suspended
                changed(suspension.isSuspended || missionControl)
            })
        }
        tokens.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.dock" else {
                return
            }
            self?.observeDock()
        })
        observeDock()
    }

    deinit {
        for token in tokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        if let dockObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(dockObserver), .commonModes)
        }
    }

    private func observeDock() {
        if let dockObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(dockObserver), .commonModes)
        }
        dockObserver = nil
        dock = nil
        missionControl = false
        changed(suspension.isSuspended)
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?
            .processIdentifier else {
            return
        }
        let element = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, context in
            guard let context else {
                return
            }
            let owner = Unmanaged<HoverFocusSystemObserver>.fromOpaque(context).takeUnretainedValue()
            owner.missionControl = (notification as String) != "AXExposeExit"
            owner.changed(owner.suspension.isSuspended || owner.missionControl)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
            return
        }
        for notification in notifications {
            AXObserverAddNotification(
                observer, element, notification as CFString, Unmanaged.passUnretained(self).toOpaque()
            )
        }
        dock = element
        dockObserver = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
}

/// Wake and session notifications can overlap; clearing one reason must not
/// resume focus while another reason still applies.
struct HoverFocusSuspension {
    var sleeping = false
    var screensSleeping = false
    var sessionInactive = false

    var isSuspended: Bool {
        sleeping || screensSleeping || sessionInactive
    }
}
