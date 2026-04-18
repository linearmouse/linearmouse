// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Foundation

/// Main-thread snapshot of the frontmost application, for readers on the event thread that cannot touch AppKit.
final class FrontmostApplicationTracker {
    static let shared = FrontmostApplicationTracker()

    private let lock = NSLock()
    private var _processIdentifier: pid_t?
    private var _bundleIdentifier: String?
    private var observer: Any?

    private init() {}

    var processIdentifier: pid_t? {
        lock.withLock { _processIdentifier }
    }

    var bundleIdentifier: String? {
        lock.withLock { _bundleIdentifier }
    }

    /// Call once from the main thread at app launch.
    func start() {
        assert(Thread.isMainThread)
        guard observer == nil else {
            return
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.update(with: application)
        }

        update(with: NSWorkspace.shared.frontmostApplication)
    }

    private func update(with application: NSRunningApplication?) {
        let pid = application?.processIdentifier
        let bundleID = application?.bundleIdentifier
        lock.withLock {
            _processIdentifier = pid
            _bundleIdentifier = bundleID
        }
    }
}
