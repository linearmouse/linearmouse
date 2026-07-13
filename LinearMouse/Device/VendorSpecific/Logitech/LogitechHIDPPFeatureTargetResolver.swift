// MIT License
// Copyright (c) 2021-2026 LinearMouse

import PointerKit

enum LogitechHIDPPFeatureTargetResolver {
    struct Target {
        let transport: LogitechHIDPPTransport
        let featureIndex: UInt8
    }

    static func resolve(
        _ featureID: LogitechHIDPPDeviceMetadataProvider.FeatureID,
        for device: VendorSpecificDeviceContext
    ) -> Target? {
        guard device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID,
              [PointerDeviceTransportName.usb, PointerDeviceTransportName.bluetoothLowEnergy]
              .contains(device.transport)
        else {
            return nil
        }

        let provider = LogitechHIDPPDeviceMetadataProvider()
        if !LogitechHIDPPDeviceMetadataProvider.isKnownReceiver(
            vendorID: device.vendorID,
            productID: device.productID
        ), let directTarget = directTarget(featureID, for: device) {
            return directTarget
        }

        if let receiverTarget = receiverTarget(featureID, for: device, provider: provider) {
            return receiverTarget
        }

        return directTarget(featureID, for: device)
    }

    private static func directTarget(
        _ featureID: LogitechHIDPPDeviceMetadataProvider.FeatureID,
        for device: VendorSpecificDeviceContext
    ) -> Target? {
        guard let transport = LogitechHIDPPTransport(device: device, deviceIndex: nil),
              let featureIndex = transport.featureIndex(for: featureID)
        else {
            return nil
        }

        return .init(transport: transport, featureIndex: featureIndex)
    }

    private static func receiverTarget(
        _ featureID: LogitechHIDPPDeviceMetadataProvider.FeatureID,
        for device: VendorSpecificDeviceContext,
        provider: LogitechHIDPPDeviceMetadataProvider
    ) -> Target? {
        guard device.transport == PointerDeviceTransportName.usb,
              let receiverChannel = provider.openReceiverChannel(for: device),
              let slot = receiverSlot(for: device, using: receiverChannel, provider: provider),
              let transport = LogitechHIDPPTransport(device: receiverChannel, deviceIndex: slot),
              let featureIndex = transport.featureIndex(for: featureID)
        else {
            return nil
        }

        return .init(transport: transport, featureIndex: featureIndex)
    }

    private static func receiverSlot(
        for device: VendorSpecificDeviceContext,
        using receiverChannel: LogitechReceiverChannel,
        provider: LogitechHIDPPDeviceMetadataProvider
    ) -> UInt8? {
        switch LogitechHIDPPDeviceMetadataProvider.receiverProtocolFamily(
            vendorID: device.vendorID,
            productID: device.productID,
            transport: device.transport
        ) {
        case .classic, .lightspeed:
            return provider.receiverSlot(for: device, using: receiverChannel)
        case .bolt:
            let discovery = provider.receiverPointingDeviceDiscovery(for: device, using: receiverChannel)
            return provider.receiverSlot(for: device, identities: discovery.identities)
        case nil:
            return provider.receiverSlot(for: device, using: receiverChannel)
        }
    }
}
