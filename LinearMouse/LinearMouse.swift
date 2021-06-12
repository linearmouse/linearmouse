//
//  LinearMouse.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/12.
//

import Foundation

class LinearMouse {
    public static var appName: String {
        get {
            return Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "(unknown)"
        }
    }

    public static var appVersion: String {
        get {
            return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "(unknown)"
        }
    }
}
