// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

enum ReceiverLogicalDeviceKind: UInt8, Hashable {
    case keyboard = 0x01
    case mouse = 0x02
    case numpad = 0x03
    case presenter = 0x04
    case remote = 0x07
    case trackball = 0x08
    case touchpad = 0x09
    case tablet = 0x0A
    case gamepad = 0x0B
    case joystick = 0x0C
    case headset = 0x0D
    case remoteControl = 0x0E
    case receiver = 0x0F

    var isPointingDevice: Bool {
        switch self {
        case .mouse, .trackball, .touchpad:
            return true
        case .keyboard,
             .numpad,
             .presenter,
             .remote,
             .tablet,
             .gamepad,
             .joystick,
             .headset,
             .remoteControl,
             .receiver:
            return false
        }
    }
}

/// HID++ uses zero as an unknown device-type marker in some connection
/// snapshots. A nonzero value that is not modelled is authoritative but
/// unsupported, so it must not inherit a pairing type.
func resolveReceiverLogicalDeviceKind(
    snapshotRaw: UInt8?,
    pairingRaw: UInt8?
) -> ReceiverLogicalDeviceKind? {
    if let snapshotRaw, snapshotRaw != 0 {
        return ReceiverLogicalDeviceKind(rawValue: snapshotRaw)
    }

    return pairingRaw.flatMap(ReceiverLogicalDeviceKind.init(rawValue:))
}

/// Produces a pointing identity only when the live snapshot does not conflict
/// with the pairing record's pointing/non-pointing classification.
func resolveReceiverPointingIdentityKind(
    snapshotRaw: UInt8?,
    pairingRaw: UInt8?
) -> ReceiverLogicalDeviceKind? {
    let snapshotKind = snapshotRaw.flatMap(ReceiverLogicalDeviceKind.init(rawValue:))
    let pairingKind = pairingRaw.flatMap(ReceiverLogicalDeviceKind.init(rawValue:))
    if snapshotKind?.isPointingDevice == true,
       pairingKind?.isPointingDevice == false,
       snapshotRaw != 0 {
        return nil
    }

    return resolveReceiverLogicalDeviceKind(snapshotRaw: snapshotRaw, pairingRaw: pairingRaw)
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
