// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// A dwell belongs to a particular physical device and window. Cancellation
/// consumes the current entry: typing or Cmd-Tab must not be undone by a timer,
/// or by a small movement within the window the pointer was already over.
struct HoverFocusState {
    struct Target: Equatable {
        let windowID: UInt32
        let pid: pid_t
        let senderID: UInt64
    }

    static let delay: TimeInterval = 0.1
    private(set) var target: Target?
    private var enteredAt: TimeInterval = 0
    private var consumed = false

    mutating func update(_ target: Target?, now: TimeInterval) -> Bool {
        guard let target else {
            self = Self()
            return false
        }
        if self.target != target {
            self.target = target
            enteredAt = now
            consumed = false
        }
        return !consumed && now - enteredAt >= Self.delay
    }

    var isWaiting: Bool {
        target != nil && !consumed
    }

    mutating func suspend() {
        consumed = true
    }
}
