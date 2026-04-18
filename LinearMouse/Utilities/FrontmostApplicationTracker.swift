// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Foundation

/// Thread-safe snapshot of the frontmost application so event-thread code can read it without
/// touching AppKit. Callers subscribe to `NSWorkspace.didActivateApplicationNotification`
/// themselves and call `update(with:)` before acting on the snapshot, avoiding any ordering race
/// between multiple observers.
final class FrontmostApplicationTracker {
    static let shared = FrontmostApplicationTracker()

    private let lock = NSLock()
    private var _processIdentifier: pid_t?
    private var _bundleIdentifier: String?

    private init() {}

    var processIdentifier: pid_t? {
        lock.withLock { _processIdentifier }
    }

    var bundleIdentifier: String? {
        lock.withLock { _bundleIdentifier }
    }

    /// Seed the snapshot from the current frontmost application. Call once from the main thread at
    /// app launch so that the first event processed before any activation notification still sees
    /// a valid value.
    func prime() {
        assert(Thread.isMainThread)
        update(with: NSWorkspace.shared.frontmostApplication)
    }

    func update(with application: NSRunningApplication?) {
        let pid = application?.processIdentifier
        let bundleID = application?.bundleIdentifier
        lock.withLock {
            _processIdentifier = pid
            _bundleIdentifier = bundleID
        }
    }
}
