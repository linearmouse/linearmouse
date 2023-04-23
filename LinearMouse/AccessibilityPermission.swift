// MIT License
// Copyright (c) 2021-2023 LinearMouse

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
}

enum AccessibilityPermissionError: Error {
    case resetError
}
