// MIT License
// Copyright (c) 2021-2026 LinearMouse

struct LogitechReceiverDiscovery {
    let identities: [ReceiverLogicalDeviceIdentity]
    let route: LogitechReceiverRoute?
}

struct LogitechReceiverRoute: Equatable {
    let slot: UInt8
    let identity: ReceiverLogicalDeviceIdentity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.slot == rhs.slot
            && lhs.identity.receiverLocationID == rhs.identity.receiverLocationID
            && lhs.identity.kind == rhs.identity.kind
            && lhs.identity.name == rhs.identity.name
            && lhs.identity.serialNumber == rhs.identity.serialNumber
            && lhs.identity.productID == rhs.identity.productID
    }

    static func hardwareTargetChanged(from previous: Self?, to current: Self?) -> Bool {
        guard let previous, let current else {
            return previous != nil || current != nil
        }

        guard previous.slot == current.slot,
              previous.identity.receiverLocationID == current.identity.receiverLocationID
        else {
            return true
        }

        if let previousSerial = previous.identity.serialNumber,
           let currentSerial = current.identity.serialNumber {
            return previousSerial != currentSerial
        }

        if let previousProductID = previous.identity.productID,
           let currentProductID = current.identity.productID {
            return previousProductID != currentProductID
        }

        return false
    }
}
