//
//  AccessibilityPermission.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/9.
//

import Foundation
import SwiftUI
import os.log

class AccessibilityPermission {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AccessibilityPermission")

    static var enabled: Bool {
        get {
            AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false
            ] as CFDictionary)
        }
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
