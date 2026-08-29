// MIT License
// Copyright (c) 2021-2026 LinearMouse

enum LogitechReceiverRouteResolver {
    static func requiresDiscovery(for device: VendorSpecificDeviceContext) -> Bool {
        LogitechHIDPPDeviceMetadataProvider.supportsReceiverMonitoring(
            vendorID: device.vendorID,
            productID: device.productID,
            transport: device.transport
        )
    }

    static func resolve(
        for device: VendorSpecificDeviceContext,
        identities: [ReceiverLogicalDeviceIdentity]
    ) -> LogitechReceiverRoute? {
        guard !identities.isEmpty else {
            return nil
        }

        let provider = LogitechHIDPPDeviceMetadataProvider()
        guard let slot = provider.receiverSlot(for: device, identities: identities),
              let identity = identities.first(where: { $0.slot == slot })
        else {
            return nil
        }

        return .init(slot: slot, identity: identity)
    }
}
