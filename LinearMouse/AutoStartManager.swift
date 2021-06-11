//
//  AutoStartManager.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/11.
//

import Foundation
import LoginServiceKit

class AutoStartManager {
    @discardableResult
    static func enable() -> Bool {
        return LoginServiceKit.addLoginItems()
    }

    @discardableResult
    static func disable() -> Bool {
        return LoginServiceKit.removeLoginItems()
    }
}
