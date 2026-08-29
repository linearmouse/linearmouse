// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

public enum HIDPPConstants {
    public static let vendorID = 0x046D
    public static let softwareID: UInt8 = 0x08
    public static let shortReportID: UInt8 = 0x10
    public static let longReportID: UInt8 = 0x11
    public static let shortReportLength = 7
    public static let longReportLength = 20
    public static let timeout: TimeInterval = 2.0
    public static let receiverIndex: UInt8 = 0xFF
    public static let directReplyIndices: Set<UInt8> = [0x00, 0xFF]
}

public enum HIDPPFeatureID: UInt16 {
    case root = 0x0000
    case deviceName = 0x0005
    case deviceFriendlyName = 0x0007
    case batteryStatus = 0x1000
    case batteryVoltage = 0x1001
    case unifiedBattery = 0x1004
    case reprogControlsV4 = 0x1B04
    case adcMeasurement = 0x1F20
    case hiresWheel = 0x2121
    case adjustableDPI = 0x2201

    public var bytes: [UInt8] {
        [UInt8(rawValue >> 8), UInt8(rawValue & 0xFF)]
    }
}

public struct HIDPPResponse: Equatable {
    public let payload: [UInt8]

    public init(payload: [UInt8]) {
        self.payload = payload
    }
}
