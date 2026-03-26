// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

struct LogitechEventContext {
    let device: Device?
    let pid: pid_t?
    let display: String?
    let controlIdentity: LogitechControlIdentity
    let isPressed: Bool
    let modifierFlags: CGEventFlags
}
