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
    private var sessionInactive = false
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
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.setSessionInactive(true)
            })
        }
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didWakeNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.setSessionInactive(false)
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

    private func setSessionInactive(_ inactive: Bool) {
        sessionInactive = inactive
        changed(sessionInactive || missionControl)
    }

    private func observeDock() {
        if let dockObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(dockObserver), .commonModes)
        }
        dockObserver = nil
        dock = nil
        missionControl = false
        changed(sessionInactive)
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
            owner.changed(owner.sessionInactive || owner.missionControl)
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
