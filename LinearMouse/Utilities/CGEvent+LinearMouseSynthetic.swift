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

        if let lhsSerial = serialNumber,
           let rhsSerial = other.serialNumber {
            return lhsSerial.caseInsensitiveCompare(rhsSerial) == .orderedSame
        }

        if let lhsProductID = productID,
           let rhsProductID = other.productID {
            return lhsProductID == rhsProductID
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
        productID = try container.decodeIfPresent(Int.self, forKey: .productID)
            ?? container.decodeIfPresent(Int.self, forKey: .logicalDeviceProductID)
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
