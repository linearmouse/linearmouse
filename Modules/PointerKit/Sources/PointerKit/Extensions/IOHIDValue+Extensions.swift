// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

public extension IOHIDValue {
    var timestamp: UInt64 {
        IOHIDValueGetTimeStamp(self)
    }

    var length: CFIndex {
        IOHIDValueGetLength(self)
    }

    var data: Data {
        Data(bytes: IOHIDValueGetBytePtr(self), count: length)
    }

    var integerValue: Int {
        IOHIDValueGetIntegerValue(self)
    }

    var element: IOHIDElement {
        IOHIDValueGetElement(self)
    }
}

extension IOHIDValue: CustomStringConvertible {
    public var description: String {
        "timestamp: \(timestamp) length: \(length) data: \(data.map { $0 }) integerValue: \(integerValue) element=(\(element))"
    }
}
