// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

protocol ReceiverActivityChannel: AnyObject {
    func switchToDJMode()
    func enableWirelessNotifications()
    func discoverPointingDeviceIdentities() -> [ReceiverLogicalDeviceIdentity]
    func waitForActivePointingSlot(timeout: TimeInterval) -> UInt8?
}
