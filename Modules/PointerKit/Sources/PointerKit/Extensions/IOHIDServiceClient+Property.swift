// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import PointerKitC

func hidPropertyValue<T>(_ value: T) -> CFTypeRef? {
    let propertyValue = value as AnyObject
    // Missing optionals bridge to NSNull, which IOKit's binary property lists
    // cannot encode. Leave the existing property unchanged instead.
    guard !(propertyValue is NSNull) else {
        return nil
    }
    return propertyValue
}

extension IOHIDServiceClient {
    func getProperty<T>(_ key: String) -> T? {
        guard let valueRef = IOHIDServiceClientCopyProperty(self, key as CFString) else {
            return nil
        }
        guard let value = valueRef as? T else {
            return nil
        }
        return value
    }

    func setProperty<T>(_ value: T, forKey: String) {
        guard let propertyValue = hidPropertyValue(value) else {
            return
        }
        IOHIDServiceClientSetProperty(self, forKey as CFString, propertyValue)
    }

    func getPropertyIOFixed(_ key: String) -> Double? {
        (getProperty(key) as IOFixed?).map { Double($0) / 65_536 }
    }

    func setPropertyIOFixed(_ value: Double?, forKey: String) {
        setProperty(value.map { IOFixed($0 * 65_536) }, forKey: forKey)
    }
}
