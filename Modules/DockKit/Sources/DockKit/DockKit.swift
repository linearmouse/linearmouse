// MIT License
// Copyright (c) 2021-2024 LinearMouse

import DockKitC
import Foundation

public func launchpad() {
    CoreDockSendNotification("com.apple.launchpad.toggle" as CFString, 0)
}

public func missionControl() {
    CoreDockSendNotification("com.apple.expose.awake" as CFString, 0)
}

public func showDesktop() {
    CoreDockSendNotification("com.apple.showdesktop.awake" as CFString, 0)
}

public func appExpose() {
    CoreDockSendNotification("com.apple.expose.front.awake" as CFString, 0)
}
