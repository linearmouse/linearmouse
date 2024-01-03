// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Foundation

enum ProcessEnvironment {
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
        !(isPreview || isRunningTest)
    }
}
