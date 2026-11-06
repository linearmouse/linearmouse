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
        static let invertModeBit: UInt8 = 0x04
        static let invertCapabilityFlag: UInt8 = 0x08
        /// The mode is three bytes. Bytes 1 and 2 are undocumented, so a mode
        /// write echoes them as read rather than clearing them.
        static let modeLength = 3
    }

    public struct Capabilities: Equatable, Sendable {
        public let multiplier: UInt8
        public let flags: UInt8

        public init(multiplier: UInt8, flags: UInt8) {
            self.multiplier = multiplier
            self.flags = flags
        }

        /// Whether the wheel can invert its direction in native HID mode.
        public var supportsInversion: Bool {
            flags & Constants.invertCapabilityFlag != 0
        }
    }

    public struct ApplyResult: Equatable, Sendable {
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
            .map { $0[0] & Constants.highResolutionModeBit != 0 }
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
        applyModeBit(
            Constants.highResolutionModeBit,
            enabled,
            deadline: deadline,
            until: shouldContinue
        )
    }

    /// Whether the wheel reports its vertical rotation inverted. The inversion
    /// happens in the device, so every host receives inverted wheel events.
    public func isWheelInverted() -> Bool? {
        isWheelInverted(deadline: nil) { true }
    }

    public func isWheelInverted(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool
    ) -> Bool? {
        readMode(deadline: deadline, until: shouldContinue)
            .map { $0[0] & Constants.invertModeBit != 0 }
    }

    public func setWheelInverted(_ inverted: Bool) -> Bool? {
        setWheelInverted(inverted, deadline: nil) { true }
    }

    /// Changes only the invert bit; the resolution and reporting target bits
    /// are written back as read.
    public func setWheelInverted(
        _ inverted: Bool,
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool
    ) -> Bool? {
        applyModeBit(
            Constants.invertModeBit,
            inverted,
            deadline: deadline,
            until: shouldContinue
        )?.appliedEnabled
    }

    private func applyModeBit(
        _ bit: UInt8,
        _ enabled: Bool,
        deadline: Date?,
        until shouldContinue: @escaping () -> Bool
    ) -> ApplyResult? {
        guard var mode = readMode(deadline: deadline, until: shouldContinue) else {
            return nil
        }

        let currentlyEnabled = mode[0] & bit != 0
        guard currentlyEnabled != enabled else {
            return ApplyResult(previousEnabled: currentlyEnabled, appliedEnabled: enabled)
        }

        if enabled {
            mode[0] |= bit
        } else {
            mode[0] &= ~bit
        }

        guard transport.request(
            featureIndex: featureIndex,
            function: Constants.setModeFunction,
            parameters: mode,
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
    ) -> [UInt8]? {
        guard let response = transport.request(
                  featureIndex: featureIndex,
                  function: Constants.getModeFunction,
                  parameters: [],
                  deadline: deadline,
                  until: shouldContinue
              ),
              !response.payload.isEmpty
        else {
            return nil
        }

        let mode = Array(response.payload.prefix(Constants.modeLength))
        return mode + [UInt8](repeating: 0, count: Constants.modeLength - mode.count)
    }
}
