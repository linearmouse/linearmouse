// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Scheme {
    struct Logitech: Codable, Equatable, ImplicitInitable {
        var highResolutionWheel: Bool?

        var smartShift: SmartShift?
    }
}

extension Scheme.Logitech {
    /// SmartShift wheel settings. Each unset field keeps the device's value.
    struct SmartShift: Codable, Equatable, ImplicitInitable {
        enum Mode: String, Codable, Equatable {
            case ratchet
            case freeSpin
        }

        enum AutoDisengage: Equatable {
            /// Wheel speed, in quarter turns per second, that releases the ratchet.
            case threshold(Int)
            /// Keep the ratchet engaged at any wheel speed.
            case never
        }

        static let thresholdRange = 1 ... 254
        static let torqueRange = 1 ... 100

        var mode: Mode?
        var autoDisengage: AutoDisengage?
        var torque: Int?

        var isEmpty: Bool {
            mode == nil && autoDisengage == nil && torque == nil
        }
    }
}

extension Scheme.Logitech {
    func merge(into logitech: inout Self) {
        if let highResolutionWheel {
            logitech.highResolutionWheel = highResolutionWheel
        }

        if let smartShift {
            smartShift.merge(into: &logitech.smartShift)
        }
    }

    func merge(into logitech: inout Self?) {
        if logitech == nil {
            logitech = Self()
        }

        merge(into: &logitech!)
    }
}

extension Scheme.Logitech.SmartShift {
    func merge(into smartShift: inout Self) {
        if let mode {
            smartShift.mode = mode
        }

        if let autoDisengage {
            smartShift.autoDisengage = autoDisengage
        }

        if let torque {
            smartShift.torque = torque
        }
    }

    func merge(into smartShift: inout Self?) {
        if smartShift == nil {
            smartShift = Self()
        }

        merge(into: &smartShift!)
    }
}

extension Scheme.Logitech.SmartShift.AutoDisengage: Codable {
    enum ValueError: Error {
        case invalidValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let threshold = try? container.decode(Int.self) {
            self = .threshold(threshold)
            return
        }

        guard try container.decode(String.self) == "never" else {
            throw CustomDecodingError(in: container, error: ValueError.invalidValue)
        }
        self = .never
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .threshold(threshold):
            try container.encode(threshold)
        case .never:
            try container.encode("never")
        }
    }
}

extension Scheme.Logitech.SmartShift.AutoDisengage.ValueError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidValue:
            return NSLocalizedString(
                "SmartShift autoDisengage must be a number or \"never\"",
                comment: ""
            )
        }
    }
}
