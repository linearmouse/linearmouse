// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Controls a SmartShift scroll wheel through either SmartShift (`0x2110`) or
/// SmartShift Wheel Enhanced (`0x2111`).
///
/// The wire format follows OpenLogi's implementation
/// (https://github.com/AprilNEA/OpenLogi, MIT OR Apache-2.0).
public struct SmartShift {
    public enum Variant: Equatable, Sendable {
        /// `0x2110`: wheel mode and automatic disengage threshold.
        case standard
        /// `0x2111`: adds tunable ratchet torque.
        case enhanced

        public var featureID: HIDPPFeatureID {
            switch self {
            case .standard:
                .smartShift
            case .enhanced:
                .smartShiftEnhanced
            }
        }
    }

    public enum WheelMode: UInt8, Equatable, Sendable {
        case freeSpin = 0x01
        case ratchet = 0x02
    }

    /// The wheel state reported by the device.
    public struct Status: Equatable, Sendable {
        /// The mode set by software or the wheel mode button. It does not
        /// report whether a ratchet is momentarily disengaged.
        public let wheelMode: WheelMode
        /// Wheel speed, in quarter turns per second, at which a ratchet
        /// disengages into free spin. `0xFF` keeps the ratchet engaged.
        public let autoDisengage: UInt8
        /// Ratchet torque in percent of the wheel's maximum force, or nil when
        /// the device does not report one.
        public let torque: UInt8?

        public init(wheelMode: WheelMode, autoDisengage: UInt8, torque: UInt8?) {
            self.wheelMode = wheelMode
            self.autoDisengage = autoDisengage
            self.torque = torque
        }
    }

    /// Fields to write. A nil field is sent as HID++'s zero "do not change"
    /// value.
    public struct Change: Equatable, Sendable {
        public var wheelMode: WheelMode?
        public var autoDisengage: UInt8?
        public var torque: UInt8?

        public init(wheelMode: WheelMode? = nil, autoDisengage: UInt8? = nil, torque: UInt8? = nil) {
            self.wheelMode = wheelMode
            self.autoDisengage = autoDisengage
            self.torque = torque
        }

        public var isEmpty: Bool {
            wheelMode == nil && autoDisengage == nil && torque == nil
        }
    }

    public struct Capabilities: Equatable, Sendable {
        public let supportsTunableTorque: Bool
        /// The wheel's factory disengage threshold, when it reports one.
        public let defaultAutoDisengage: UInt8?

        public init(supportsTunableTorque: Bool, defaultAutoDisengage: UInt8? = nil) {
            self.supportsTunableTorque = supportsTunableTorque
            self.defaultAutoDisengage = defaultAutoDisengage
        }
    }

    public static let permanentRatchet: UInt8 = 0xFF
    public static let autoDisengageRange: ClosedRange<UInt8> = 1 ... 0xFF
    public static let torqueRange: ClosedRange<UInt8> = 1 ... 100

    private enum Constants {
        static let standardGetFunction: UInt8 = 0x00
        static let standardSetFunction: UInt8 = 0x01
        static let enhancedGetCapabilitiesFunction: UInt8 = 0x00
        static let enhancedGetFunction: UInt8 = 0x01
        static let enhancedSetFunction: UInt8 = 0x02
        static let tunableTorqueCapability: UInt8 = 0x01
    }

    public let variant: Variant
    /// Whether torque writes are applied. Only the `0x2111` capability bit
    /// says so; a status reply's torque byte is not a capability claim.
    public let supportsTunableTorque: Bool
    public let defaultAutoDisengage: UInt8?
    private let transport: HIDPPTransport
    private let featureIndex: UInt8

    public init(
        transport: HIDPPTransport,
        featureIndex: UInt8,
        variant: Variant,
        supportsTunableTorque: Bool = false,
        defaultAutoDisengage: UInt8? = nil
    ) {
        self.transport = transport
        self.featureIndex = featureIndex
        self.variant = variant
        self.supportsTunableTorque = variant == .enhanced && supportsTunableTorque
        self.defaultAutoDisengage = defaultAutoDisengage
    }

    /// Reads the capabilities once, so writes need no further capability I/O.
    public init?(
        transport: HIDPPTransport,
        featureIndex: UInt8,
        variant: Variant,
        deadline: Date?,
        until shouldContinue: @escaping () -> Bool
    ) {
        let probe = Self(transport: transport, featureIndex: featureIndex, variant: variant)
        guard let capabilities = probe.capabilities(deadline: deadline, until: shouldContinue) else {
            return nil
        }
        self.init(
            transport: transport,
            featureIndex: featureIndex,
            variant: variant,
            supportsTunableTorque: capabilities.supportsTunableTorque,
            defaultAutoDisengage: capabilities.defaultAutoDisengage
        )
    }

    public var receiverSlot: UInt8? {
        transport.receiverSlot
    }

    public func capabilities(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> Capabilities? {
        // `0x2111` has a capabilities function. `0x2110` reports its default
        // threshold as the third byte of its status reply instead.
        let function = variant == .enhanced
            ? Constants.enhancedGetCapabilitiesFunction
            : Constants.standardGetFunction
        guard let response = transport.request(
            featureIndex: featureIndex,
            function: function,
            parameters: [],
            deadline: deadline,
            until: shouldContinue
        ) else {
            return nil
        }

        let payload = response.payload
        let defaultIndex = variant == .enhanced ? 1 : 2
        let defaultAutoDisengage = payload.indices.contains(defaultIndex)
            ? payload[defaultIndex]
            : nil
        return Capabilities(
            supportsTunableTorque: variant == .enhanced
                && payload.first.map { $0 & Constants.tunableTorqueCapability != 0 } == true,
            defaultAutoDisengage: defaultAutoDisengage.flatMap {
                Self.autoDisengageRange.contains($0) && $0 != Self.permanentRatchet ? $0 : nil
            }
        )
    }

    public func status(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> Status? {
        let function = variant == .enhanced ? Constants.enhancedGetFunction : Constants.standardGetFunction
        guard let response = transport.request(
            featureIndex: featureIndex,
            function: function,
            parameters: [],
            deadline: deadline,
            until: shouldContinue
        ) else {
            return nil
        }

        return Self.parseStatus(response.payload, variant: variant)
    }

    /// Writes the non-nil fields and returns the status the device replies
    /// with. The reply is advisory; callers confirm a write by reading back.
    /// Torque is dropped unless the wheel advertises tunable torque. It is
    /// never written through `0x2110`, whose third byte is the default
    /// disengage threshold instead.
    public func apply(
        _ change: Change,
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> Status? {
        var change = change
        if !supportsTunableTorque {
            change.torque = nil
        }
        guard !change.isEmpty, Self.isWritable(change) else {
            return nil
        }

        let function = variant == .enhanced ? Constants.enhancedSetFunction : Constants.standardSetFunction
        guard let response = transport.request(
            featureIndex: featureIndex,
            function: function,
            parameters: Self.parameters(for: change, variant: variant),
            deadline: deadline,
            until: shouldContinue
        ) else {
            return nil
        }

        return Self.parseStatus(response.payload, variant: variant)
    }

    static func isWritable(_ change: Change) -> Bool {
        change.autoDisengage.map { autoDisengageRange.contains($0) } != false
            && change.torque.map { torqueRange.contains($0) } != false
    }

    static func parameters(for change: Change, variant: Variant) -> [UInt8] {
        [
            change.wheelMode?.rawValue ?? 0,
            change.autoDisengage ?? 0,
            variant == .enhanced ? change.torque ?? 0 : 0
        ]
    }

    static func parseStatus(_ payload: [UInt8], variant: Variant) -> Status? {
        guard payload.count >= 3,
              let wheelMode = WheelMode(rawValue: payload[0]),
              autoDisengageRange.contains(payload[1])
        else {
            return nil
        }

        let torque: UInt8?
        if variant == .enhanced, payload[2] != 0 {
            guard torqueRange.contains(payload[2]) else {
                return nil
            }
            torque = payload[2]
        } else {
            torque = nil
        }

        return Status(wheelMode: wheelMode, autoDisengage: payload[1], torque: torque)
    }
}
