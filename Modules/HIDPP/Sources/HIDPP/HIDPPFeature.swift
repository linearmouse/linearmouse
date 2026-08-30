// MIT License
// Copyright (c) 2021-2026 LinearMouse

public protocol HIDPPFeature {
    static var featureID: HIDPPFeatureID { get }

    init(transport: HIDPPTransport, featureIndex: UInt8)
}
