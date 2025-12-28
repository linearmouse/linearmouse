// MIT License
// Copyright (c) 2021-2025 LinearMouse

import PointerKitC

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

    @discardableResult
    func setProperty<T>(_ value: T, forKey: String) -> Bool {
        IOHIDServiceClientSetProperty(self, forKey as CFString, value as AnyObject)
    }

    func getPropertyIOFixed(_ key: String) -> Double? {
        (getProperty(key) as IOFixed?).map { Double($0) / 65_536 }
    }

    @discardableResult
    func setPropertyIOFixed(_ value: Double?, forKey: String) -> Bool {
        setProperty(value.map { IOFixed($0 * 65_536) }, forKey: forKey)
    }
}
