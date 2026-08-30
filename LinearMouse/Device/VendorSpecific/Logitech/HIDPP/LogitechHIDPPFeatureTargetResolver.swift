// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP
import PointerKit

/// Resolves a HID++ feature to either a direct device or receiver-routed target.
enum LogitechHIDPPFeatureTargetResolver {
    struct Target {
        let transport: HIDPPTransport
        let featureIndex: UInt8
    }

    /// Resolves a production device using the receiver monitor's route. Monitored
    /// receivers deliberately remain unavailable until discovery supplies a slot.
    static func resolve(
        _ featureID: HIDPPFeatureID,
        for device: VendorSpecificDeviceContext,
        receiverSlot: UInt8?,
        requestDeadline: Date? = nil,
        requestShouldContinue: @escaping () -> Bool = { true },
        shouldContinue: @escaping () -> Bool
    ) -> Target? {
        guard device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID,
              [PointerDeviceTransportName.usb, PointerDeviceTransportName.bluetoothLowEnergy]
              .contains(device.transport)
        else {
            return nil
        }

        let isKnownReceiver = LogitechHIDPPDeviceMetadataProvider.isKnownReceiver(
            vendorID: device.vendorID,
            productID: device.productID
        )
        let hasReceiverMonitor = LogitechHIDPPDeviceMetadataProvider.supportsReceiverMonitoring(
            vendorID: device.vendorID,
            productID: device.productID,
            transport: device.transport
        )

        if !isKnownReceiver {
            if let directTarget = directTarget(
                featureID,
                for: device,
                requestDeadline: requestDeadline,
                requestShouldContinue: requestShouldContinue,
                shouldContinue: shouldContinue
            ) {
                return directTarget
            }

            guard device.transport == PointerDeviceTransportName.usb else {
                return nil
            }

            return receiverTarget(
                featureID,
                for: device,
                provider: LogitechHIDPPDeviceMetadataProvider(),
                requestDeadline: requestDeadline,
                requestShouldContinue: requestShouldContinue,
                shouldContinue: shouldContinue
            )
        }

        // Older receiver families do not yet have a monitor/readiness signal.
        // Preserve their existing on-demand routing fallback.
        guard hasReceiverMonitor else {
            return receiverTarget(
                featureID,
                for: device,
                provider: LogitechHIDPPDeviceMetadataProvider(),
                requestDeadline: requestDeadline,
                requestShouldContinue: requestShouldContinue,
                shouldContinue: shouldContinue
            ) ?? directTarget(
                featureID,
                for: device,
                requestDeadline: requestDeadline,
                requestShouldContinue: requestShouldContinue,
                shouldContinue: shouldContinue
            )
        }

        guard let receiverSlot else {
            return nil
        }

        let provider = LogitechHIDPPDeviceMetadataProvider()
        guard let receiverChannel = provider.openReceiverChannel(for: device) else {
            return nil
        }

        return receiverTarget(
            featureID,
            receiverChannel: receiverChannel,
            slot: receiverSlot,
            requestDeadline: requestDeadline,
            requestShouldContinue: requestShouldContinue,
            shouldContinue: shouldContinue
        )
    }

    private static func directTarget(
        _ featureID: HIDPPFeatureID,
        for device: VendorSpecificDeviceContext,
        requestDeadline: Date?,
        requestShouldContinue: @escaping () -> Bool,
        shouldContinue: @escaping () -> Bool = { true }
    ) -> Target? {
        guard let transport = HIDPPTransport(
            device: device,
            deviceIndex: nil,
            shouldContinue: shouldContinue
        ),
            let featureIndex = transport.featureIndex(
                for: featureID,
                deadline: requestDeadline,
                until: requestShouldContinue
            )
        else {
            return nil
        }

        return .init(transport: transport, featureIndex: featureIndex)
    }

    private static func receiverTarget(
        _ featureID: HIDPPFeatureID,
        for device: VendorSpecificDeviceContext,
        provider: LogitechHIDPPDeviceMetadataProvider,
        requestDeadline: Date?,
        requestShouldContinue: @escaping () -> Bool,
        shouldContinue: @escaping () -> Bool = { true }
    ) -> Target? {
        guard device.transport == PointerDeviceTransportName.usb,
              let receiverChannel = provider.openReceiverChannel(for: device),
              let slot = receiverSlot(for: device, using: receiverChannel, provider: provider)
        else {
            return nil
        }

        return receiverTarget(
            featureID,
            receiverChannel: receiverChannel,
            slot: slot,
            requestDeadline: requestDeadline,
            requestShouldContinue: requestShouldContinue,
            shouldContinue: shouldContinue
        )
    }

    private static func receiverTarget(
        _ featureID: HIDPPFeatureID,
        receiverChannel: LogitechReceiverChannel,
        slot: UInt8,
        requestDeadline: Date?,
        requestShouldContinue: @escaping () -> Bool,
        shouldContinue: @escaping () -> Bool = { true }
    ) -> Target? {
        guard let transport = HIDPPTransport(
            device: receiverChannel,
            deviceIndex: slot,
            shouldContinue: shouldContinue
        ),
            let featureIndex = transport.featureIndex(
                for: featureID,
                deadline: requestDeadline,
                until: requestShouldContinue
            )
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
            return provider.receiverSlot(for: device, discovery: discovery)
        case nil:
            return provider.receiverSlot(for: device, using: receiverChannel)
        }
    }
}

extension HIDPPFeature {
    init?(
        device: VendorSpecificDeviceContext,
        receiverSlot: UInt8?,
        requestDeadline: Date? = nil,
        requestShouldContinue: @escaping () -> Bool = { true },
        shouldContinue: @escaping () -> Bool
    ) {
        guard let target = LogitechHIDPPFeatureTargetResolver.resolve(
            Self.featureID,
            for: device,
            receiverSlot: receiverSlot,
            requestDeadline: requestDeadline,
            requestShouldContinue: requestShouldContinue,
            shouldContinue: shouldContinue
        ) else {
            return nil
        }

        self.init(transport: target.transport, featureIndex: target.featureIndex)
    }
}
