// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

enum ReceiverLogicalDeviceKind: UInt8, Hashable {
    case keyboard = 0x01
    case mouse = 0x02
    case numpad = 0x03
    case trackball = 0x08
    case touchpad = 0x09

    var isPointingDevice: Bool {
        switch self {
        case .mouse, .trackball, .touchpad:
            return true
        case .keyboard, .numpad:
            return false
        }
    }
}

struct ReceiverLogicalDeviceIdentity: Hashable {
    let receiverLocationID: Int
    let slot: UInt8
    let kind: ReceiverLogicalDeviceKind
    let name: String
    let serialNumber: String?
    let productID: Int?
    let batteryLevel: Int?

    func isSameLogicalDevice(as other: Self) -> Bool {
        receiverLocationID == other.receiverLocationID && slot == other.slot
    }
}
