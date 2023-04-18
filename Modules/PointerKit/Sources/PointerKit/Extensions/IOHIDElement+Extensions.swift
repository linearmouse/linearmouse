// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

public extension IOHIDElement {
    var usagePage: UInt32 {
        IOHIDElementGetUsagePage(self)
    }

    var usage: UInt32 {
        IOHIDElementGetUsage(self)
    }
}

extension IOHIDElement: CustomStringConvertible {
    public var description: String {
        String(format: "usagePage: %02X usage: %02X", usagePage, usage)
    }
}
