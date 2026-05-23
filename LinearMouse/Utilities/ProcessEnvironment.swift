// MIT License
// Copyright (c) 2021-2026 LinearMouse

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
            let environment = ProcessInfo.processInfo.environment
            let testEnvironmentKeys = [
                "XCTestConfigurationFilePath",
                "XCTestSessionIdentifier",
                "XCInjectBundle",
                "XCInjectBundleInto"
            ]

            return testEnvironmentKeys.contains { environment[$0] != nil } ||
                Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") } ||
                NSClassFromString("XCTestCase") != nil ||
                NSClassFromString("XCTest.XCTestCase") != nil
        #else
            return false
        #endif
    }

    static var isRunningApp: Bool {
        !(isPreview || isRunningTest)
    }
}
