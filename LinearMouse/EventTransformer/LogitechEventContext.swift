// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

struct LogitechEventContext {
    let device: Device?
    let pid: pid_t?
    let display: String?
    let mouseLocation: CGPoint
    let controlIdentity: LogitechControlIdentity
    let allowsIdentityFallback: Bool
    let isPressed: Bool
    let modifierFlags: CGEventFlags

    init(
        device: Device?,
        pid: pid_t?,
        display: String?,
        mouseLocation: CGPoint,
        controlIdentity: LogitechControlIdentity,
        allowsIdentityFallback: Bool = false,
        isPressed: Bool,
        modifierFlags: CGEventFlags
    ) {
        self.device = device
        self.pid = pid
        self.display = display
        self.mouseLocation = mouseLocation
        self.controlIdentity = controlIdentity
        self.allowsIdentityFallback = allowsIdentityFallback
        self.isPressed = isPressed
        self.modifierFlags = modifierFlags
    }

    func matches(_ identity: LogitechControlIdentity) -> Bool {
        controlIdentity.matches(identity, allowingIdentityFallback: allowsIdentityFallback)
    }
}
