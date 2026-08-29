// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

public struct HiResWheel {
    private enum Constants {
        static let getCapabilitiesFunction: UInt8 = 0x00
        static let getModeFunction: UInt8 = 0x01
        static let setModeFunction: UInt8 = 0x02
        static let highResolutionModeBit: UInt8 = 0x02
    }

    public struct Capabilities: Equatable {
        public let multiplier: UInt8
        public let flags: UInt8

        public init(multiplier: UInt8, flags: UInt8) {
            self.multiplier = multiplier
            self.flags = flags
        }
    }

    public struct ApplyResult: Equatable {
        public let previousEnabled: Bool
        public let appliedEnabled: Bool

        public init(previousEnabled: Bool, appliedEnabled: Bool) {
            self.previousEnabled = previousEnabled
            self.appliedEnabled = appliedEnabled
        }
    }

    private let transport: HIDPPTransport
    private let featureIndex: UInt8

    public init(transport: HIDPPTransport, featureIndex: UInt8) {
        self.transport = transport
        self.featureIndex = featureIndex
    }

    public func capabilities() -> Capabilities? {
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

    public func isHighResolutionWheelEnabled() -> Bool? {
        readMode().map { $0 & Constants.highResolutionModeBit != 0 }
    }

    public func setHighResolutionWheelEnabled(_ enabled: Bool) -> Bool? {
        applyHighResolutionWheelEnabled(enabled)?.appliedEnabled
    }

    public func applyHighResolutionWheelEnabled(_ enabled: Bool) -> ApplyResult? {
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
