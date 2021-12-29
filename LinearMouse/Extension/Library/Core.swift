//
//  Core.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/1/6.
//

import Foundation

class Core: Library {
    func registerInContext(_ context: JSContext) {
        context.globalObject.defineProperty("__APP_VERSION__", descriptor: [
            JSPropertyDescriptorValueKey: LinearMouse.appVersion
        ])
    }
}
