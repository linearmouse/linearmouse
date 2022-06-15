//
//  Environment.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/15.
//

import Foundation

struct Environment {
    static var isPreview: Bool {
#if DEBUG
        return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
#else
        return false
#endif
    }

    static var isRunningTest: Bool {
#if DEBUG
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
#else
        return false
#endif
    }

    static var isRunningApp: Bool {
        return !(isPreview || isRunningTest)
    }
}
