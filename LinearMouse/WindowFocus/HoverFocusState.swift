// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Each entry belongs to a particular physical device and window. Cancellation
/// consumes the current entry: typing or Cmd-Tab must not be undone by a timer,
/// or by a small movement within the window the pointer was already over.
struct HoverFocusState {
    struct Target: Equatable {
        let windowID: UInt32
        let pid: pid_t
        let senderID: UInt64
    }

    private(set) var target: Target?
    private var consumed = false

    mutating func update(_ target: Target?) -> Bool {
        guard let target else {
            self = Self()
            return false
        }
        if self.target != target {
            self.target = target
            consumed = false
        }
        return !consumed
    }

    var isWaiting: Bool {
        target != nil && !consumed
    }

    mutating func suspend() {
        consumed = true
    }
}
