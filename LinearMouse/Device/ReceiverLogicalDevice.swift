// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import PointerKit

final class ReceiverLogicalDevice: Device {
    let identity: ReceiverLogicalDeviceIdentity
    let receiverDevice: Device

    override var isLogicalDevice: Bool {
        true
    }

    override var identityHashValue: AnyHashable {
        AnyHashable(identity)
    }

    init(_ manager: DeviceManager, receiverDevice: Device, identity: ReceiverLogicalDeviceIdentity) {
        self.identity = identity
        self.receiverDevice = receiverDevice

        super.init(manager, receiverDevice.pointerDevice, observeInputs: false)

        vendorID = receiverDevice.vendorID
        productID = identity.productID ?? receiverDevice.productID
        serialNumber = identity.serialNumber ?? receiverDevice.serialNumber
        buttonCount = receiverDevice.buttonCount
        name = identity.name
        productName = identity.name
        batteryLevel = identity.batteryLevel
        participatesInActiveTracking = false
    }

    override var category: Category {
        switch identity.kind {
        case .touchpad:
            return .trackpad
        case .mouse, .trackball:
            return .mouse
        case .keyboard, .numpad:
            return receiverDevice.category
        }
    }
}
