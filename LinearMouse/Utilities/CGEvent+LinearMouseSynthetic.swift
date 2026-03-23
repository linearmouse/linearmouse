// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Foundation

struct LogitechControlIdentity: Codable, Equatable, Hashable {
    static let kind = "logitechControl"

    var controlID: Int
    var productID: Int?
    var serialNumber: String?
}

extension LogitechControlIdentity {
    var specificityScore: Int {
        if serialNumber != nil {
            return 2
        }

        if productID != nil {
            return 1
        }

        return 0
    }

    var userVisibleName: String {
        String(format: "Logitech Control 0x%04X", controlID)
    }

    var controlIDValue: UInt16? {
        UInt16(exactly: controlID)
    }

    func matches(_ other: LogitechControlIdentity) -> Bool {
        guard controlID == other.controlID else {
            return false
        }

        if let configuredSerialNumber = other.serialNumber {
            guard let serialNumber else {
                return false
            }
            return serialNumber.caseInsensitiveCompare(configuredSerialNumber) == .orderedSame
        }

        if let configuredProductID = other.productID {
            guard let productID else {
                return false
            }
            return productID == configuredProductID
        }

        return other.serialNumber == nil && other.productID == nil
    }
}

extension LogitechControlIdentity {
    private enum CodingKeys: String, CodingKey {
        case kind
        case controlID
        case productID
        case serialNumber
        case logicalDeviceProductID
        case logicalDeviceSerialNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        controlID = try container.decode(Int.self, forKey: .controlID)
        productID = try decodeProductID(in: container, keys: [.productID, .logicalDeviceProductID])
        serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
            ?? container.decodeIfPresent(String.self, forKey: .logicalDeviceSerialNumber)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.kind, forKey: .kind)
        try container.encode(controlID, forKey: .controlID)
        try container.encodeIfPresent(productID, forKey: .productID)
        try container.encodeIfPresent(serialNumber, forKey: .serialNumber)
    }

    private func decodeProductID(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) throws -> Int? {
        for key in keys {
            if let value = try? container.decode(Int.self, forKey: key) {
                return value
            }

            if let hexValue = try? container.decode(String.self, forKey: key) {
                let normalized = hexValue.hasPrefix("0x") ? String(hexValue.dropFirst(2)) : hexValue
                guard let parsed = Int(normalized, radix: 16) else {
                    throw CustomDecodingError(in: container, error: ValueError.invalidProductID)
                }
                return parsed
            }
        }

        return nil
    }

    private enum ValueError: LocalizedError {
        case invalidProductID

        var errorDescription: String? {
            switch self {
            case .invalidProductID:
                return NSLocalizedString("Invalid Logitech productID", comment: "")
            }
        }
    }
}

extension CGEvent {
    private static let linearMouseSyntheticEventUserData: Int64 = 0x534D_4F4F_5448

    var isLinearMouseSyntheticEvent: Bool {
        get {
            getIntegerValueField(.eventSourceUserData) == Self.linearMouseSyntheticEventUserData
        }
        set {
            setIntegerValueField(
                .eventSourceUserData,
                value: newValue ? Self.linearMouseSyntheticEventUserData : 0
            )
        }
    }
}
