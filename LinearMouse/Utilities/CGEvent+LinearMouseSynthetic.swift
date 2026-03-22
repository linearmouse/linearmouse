// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Foundation

struct LogitechControlIdentity: Codable, Equatable, Hashable {
    var controlID: Int
    var logicalDeviceProductID: Int?
    var logicalDeviceSerialNumber: String?
}

extension LogitechControlIdentity {
    var userVisibleName: String {
        String(format: "Logitech CID 0x%04X", controlID)
    }

    var controlIDValue: UInt16? {
        UInt16(exactly: controlID)
    }

    func matches(_ other: LogitechControlIdentity) -> Bool {
        guard controlID == other.controlID else {
            return false
        }

        if let lhsSerial = logicalDeviceSerialNumber,
           let rhsSerial = other.logicalDeviceSerialNumber {
            return lhsSerial.caseInsensitiveCompare(rhsSerial) == .orderedSame
        }

        if let lhsProductID = logicalDeviceProductID,
           let rhsProductID = other.logicalDeviceProductID {
            return lhsProductID == rhsProductID
        }

        return other.logicalDeviceSerialNumber == nil && other.logicalDeviceProductID == nil
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
