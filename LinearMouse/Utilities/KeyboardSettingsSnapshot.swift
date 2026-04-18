// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Foundation

/// Main-thread snapshot of keyboard-repeat timings so event-thread code can read them without touching AppKit.
///
/// `NSEvent.keyRepeatDelay` / `NSEvent.keyRepeatInterval` do not auto-update; refresh at app launch and
/// when the session becomes active.
final class KeyboardSettingsSnapshot {
    static let shared = KeyboardSettingsSnapshot()

    private let lock = NSLock()
    private var _keyRepeatDelay: TimeInterval = 0
    private var _keyRepeatInterval: TimeInterval = 0

    private init() {}

    var keyRepeatDelay: TimeInterval {
        lock.withLock { _keyRepeatDelay }
    }

    var keyRepeatInterval: TimeInterval {
        lock.withLock { _keyRepeatInterval }
    }

    /// Call from the main thread.
    func refresh() {
        assert(Thread.isMainThread)
        let delay = NSEvent.keyRepeatDelay
        let interval = NSEvent.keyRepeatInterval
        lock.withLock {
            _keyRepeatDelay = delay
            _keyRepeatInterval = interval
        }
    }
}
