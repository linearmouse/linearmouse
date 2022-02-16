//
//  IOHIDServiceClient+CustomStringConvertible.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/2/14.
//

import Foundation

extension IOHIDServiceClient: CustomStringConvertible {
    private var product: String? {
        getProperty(kIOHIDProductKey)
    }

    private var vendorID: Int? {
        getProperty(kIOHIDVendorIDKey)
    }

    private var productID: Int? {
        getProperty(kIOHIDProductIDKey)
    }

    public var description: String {
        String(format: "%@ (VID=0x%04X, PID=0x%04X)", product ?? "<unknown>", vendorID ?? 0, productID ?? 0)
    }
}
