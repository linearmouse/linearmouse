// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import os.log
import SwiftUI

class AccessibilityPermission {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AccessibilityPermission")

    static var enabled: Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false
        ] as CFDictionary)
    }

    static func prompt() {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true
        ] as CFDictionary)
    }

    static func pollingUntilEnabled(completion: @escaping () -> Void) {
        guard enabled else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                os_log("Polling accessibility permission", log: log, type: .debug)
                pollingUntilEnabled(completion: completion)
            }
            return
        }
        completion()
    }

    static func reset() throws {
        let command = "do shell script \"tccutil reset Accessibility\" with administrator privileges"

        guard let script = NSAppleScript(source: command) else {
            os_log("Failed to reset Accessibility permissions", log: Self.log, type: .error)
            return
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)

        if let error = error {
            throw AccessibilityPermissionError.resetError(error)
        }
    }
}

enum AccessibilityPermissionError: Error {
    case resetError(NSDictionary)
}
