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

    /// The base directory for user-specific configuration files, as defined by the
    /// XDG Base Directory Specification.
    ///
    /// Returns `nil` unless `XDG_CONFIG_HOME` holds an absolute path. The specification
    /// requires unset, empty and relative values to be ignored, so that callers fall back
    /// to the `~/.config` default.
    static func xdgConfigHome(from environment: [String: String]) -> URL? {
        guard let path = environment["XDG_CONFIG_HOME"], path.hasPrefix("/") else {
            return nil
        }

        // `isDirectory: true` is required: without it Foundation probes the file system to
        // decide, and a directory that does not exist yet is treated as a file, which makes
        // `URL(fileURLWithPath:relativeTo:)` resolve against its parent.
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static var xdgConfigHome: URL? {
        xdgConfigHome(from: ProcessInfo.processInfo.environment)
    }
}
