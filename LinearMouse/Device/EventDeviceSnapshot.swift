// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Publishes device routing from the main thread to the event thread without
/// exposing either manager's mutable device dictionary.
final class EventDeviceSnapshot<Device: AnyObject> {
    private let lock = NSLock()
    private var devices = [UInt64: Device]()
    private weak var lastActiveDevice: Device?

    func replaceDevices(_ devices: [UInt64: Device]) {
        let retiredDevices = lock.withLock {
            let previousDevices = self.devices
            self.devices = devices
            return previousDevices
        }

        // Device teardown can reenter routing. Release retired devices only
        // after unlocking, even when this snapshot held their last reference.
        withExtendedLifetime(retiredDevices) {}
    }

    func setLastActiveDevice(_ device: Device?) {
        lock.withLock {
            lastActiveDevice = device
        }
    }

    func device(for senderID: UInt64?) -> Device? {
        lock.withLock {
            if let senderID, let device = devices[senderID] {
                return device
            }

            // Retain the result while holding the lock so replacement cannot
            // destroy a device between the lookup and the caller's retain.
            return lastActiveDevice
        }
    }
}
