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
}
