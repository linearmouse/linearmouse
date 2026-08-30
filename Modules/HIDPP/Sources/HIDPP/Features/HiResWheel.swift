// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

public struct HiResWheel: HIDPPFeature {
    public static let featureID = HIDPPFeatureID.hiresWheel

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

    public var receiverSlot: UInt8? {
        transport.receiverSlot
    }

    public func capabilities() -> Capabilities? {
        capabilities(deadline: nil) { true }
    }

    public func capabilities(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool
    ) -> Capabilities? {
        guard let response = transport.request(
            featureIndex: featureIndex,
            function: Constants.getCapabilitiesFunction,
            parameters: [],
            deadline: deadline,
            until: shouldContinue
        ),
            response.payload.count >= 2
        else {
            return nil
        }

        return Capabilities(multiplier: response.payload[0], flags: response.payload[1])
    }

    public func isHighResolutionWheelEnabled() -> Bool? {
        isHighResolutionWheelEnabled(deadline: nil) { true }
    }

    public func isHighResolutionWheelEnabled(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool
    ) -> Bool? {
        readMode(deadline: deadline, until: shouldContinue)
            .map { $0 & Constants.highResolutionModeBit != 0 }
    }

    public func setHighResolutionWheelEnabled(_ enabled: Bool) -> Bool? {
        setHighResolutionWheelEnabled(
            enabled,
            deadline: nil
        ) { true }
    }

    public func setHighResolutionWheelEnabled(
        _ enabled: Bool,
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool
    ) -> Bool? {
        applyHighResolutionWheelEnabled(
            enabled,
            deadline: deadline,
            until: shouldContinue
        )?.appliedEnabled
    }

    public func applyHighResolutionWheelEnabled(_ enabled: Bool) -> ApplyResult? {
        applyHighResolutionWheelEnabled(
            enabled,
            deadline: nil
        ) { true }
    }

    public func applyHighResolutionWheelEnabled(
        _ enabled: Bool,
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool
    ) -> ApplyResult? {
        guard var mode = readMode(deadline: deadline, until: shouldContinue) else {
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
            parameters: [mode],
            deadline: deadline,
            until: shouldContinue
        ) != nil else {
            return nil
        }

        return ApplyResult(previousEnabled: currentlyEnabled, appliedEnabled: enabled)
    }

    private func readMode(
        deadline: Date?,
        until shouldContinue: @escaping () -> Bool
    ) -> UInt8? {
        guard let response = transport.request(
            featureIndex: featureIndex,
            function: Constants.getModeFunction,
            parameters: [],
            deadline: deadline,
            until: shouldContinue
        ),
            let mode = response.payload.first
        else {
            return nil
        }

        return mode
    }
}
