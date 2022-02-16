//
//  IOHIDServiceClient+Extension.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/2/14.
//

import Foundation

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
        IOHIDServiceClientSetProperty(self, forKey as CFString, value as AnyObject)
    }
}
