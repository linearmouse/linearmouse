// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

struct LogitechHIDPPHighResolutionWheelController {
    private enum Constants {
        static let getCapabilitiesFunction: UInt8 = 0x00
        static let getModeFunction: UInt8 = 0x01
        static let setModeFunction: UInt8 = 0x02
        static let highResolutionModeBit: UInt8 = 0x02
    }

    struct Capabilities: Equatable {
        let multiplier: UInt8
        let flags: UInt8
    }

    struct ApplyResult: Equatable {
        let previousEnabled: Bool
        let appliedEnabled: Bool
    }

    private let transport: LogitechHIDPPTransport
    private let featureIndex: UInt8

    init?(device: VendorSpecificDeviceContext) {
        guard let target = LogitechHIDPPFeatureTargetResolver.resolve(.hiresWheel, for: device)
        else {
            return nil
        }

        self.init(transport: target.transport, featureIndex: target.featureIndex)
    }

    init(transport: LogitechHIDPPTransport, featureIndex: UInt8) {
        self.transport = transport
        self.featureIndex = featureIndex
    }

    func capabilities() -> Capabilities? {
        guard let response = transport.request(
            featureIndex: featureIndex,
            function: Constants.getCapabilitiesFunction,
            parameters: []
        ),
            response.payload.count >= 2
        else {
            return nil
        }

        return Capabilities(multiplier: response.payload[0], flags: response.payload[1])
    }

    func isHighResolutionWheelEnabled() -> Bool? {
        readMode().map { $0 & Constants.highResolutionModeBit != 0 }
    }

    func setHighResolutionWheelEnabled(_ enabled: Bool) -> Bool? {
        applyHighResolutionWheelEnabled(enabled)?.appliedEnabled
    }

    func applyHighResolutionWheelEnabled(_ enabled: Bool) -> ApplyResult? {
        guard var mode = readMode() else {
            return nil
        }

        let currentlyEnabled = mode & Constants.highResolutionModeBit != 0
        guard currentlyEnabled != enabled else {
            return ApplyResult(previousEnabled: currentlyEnabled, appliedEnabled: enabled)
        }

        if enabled {
            mode |= Constants.highResolutionModeBit
        } else {
            mode &= ~Constants.highResolutionModeBit
        }

        guard transport.request(
            featureIndex: featureIndex,
            function: Constants.setModeFunction,
            parameters: [mode]
        ) != nil else {
            return nil
        }

        return ApplyResult(previousEnabled: currentlyEnabled, appliedEnabled: enabled)
    }

    private func readMode() -> UInt8? {
        guard let response = transport.request(
            featureIndex: featureIndex,
            function: Constants.getModeFunction,
            parameters: []
        ),
            let mode = response.payload.first
        else {
            return nil
        }

        return mode
    }
}
