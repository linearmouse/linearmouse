// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import IOKit.hidsystem
import os.log

/// AX access is also needed for window focus actions, independently of event posting.
enum AccessibilityPermission {
    private static let queue = DispatchQueue(label: "app.linearmouse.permissions", qos: .utility)
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AccessibilityPermission")

    struct Snapshot {
        let accessibility: Bool
        let postEvent: Bool
        let hidPostEvent: IOHIDAccessType

        var enabled: Bool {
            // AX and CG preflight can retain stale grants after a permission is revoked.
            // IOHIDCheckAccess also detects removal of the entry (unknown).
            accessibility && hidPostEvent == kIOHIDAccessTypeGranted
        }
    }

    /// A newly granted AX permission can precede event access in the current process.
    /// Permit one restart for that transition; startup still validates all permissions.
    struct AuthorizationProgress {
        private var observedUntrustedAccessibility: Bool
        private var completed = false

        init(accessibilityInitiallyTrusted: Bool) {
            observedUntrustedAccessibility = !accessibilityInitiallyTrusted
        }

        mutating func shouldRestart(after snapshot: Snapshot, isDragging: Bool) -> Bool {
            if !snapshot.accessibility {
                observedUntrustedAccessibility = true
            }
            let newlyGranted = observedUntrustedAccessibility && snapshot.accessibility
            guard !completed, !isDragging, snapshot.enabled || newlyGranted else {
                return false
            }
            completed = true
            return true
        }
    }

    static var enabled: Bool {
        AXIsProcessTrusted()
    }

    static func check(completion: @escaping (Snapshot) -> Void) {
        // IOHIDCheckAccess performs blocking IPC to tccd. Never call it on the event thread.
        queue.async {
            let snapshot = Snapshot(
                accessibility: enabled,
                postEvent: CGPreflightPostEventAccess(),
                hidPostEvent: IOHIDCheckAccess(kIOHIDRequestTypePostEvent)
            )
            os_log(
                "Permission check: AX=%{public}d, PostEvent=%{public}d, HIDPostEvent=%{public}d",
                log: log,
                type: .info,
                snapshot.accessibility,
                snapshot.postEvent,
                snapshot.hidPostEvent.rawValue
            )
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    /// Used only to finish setting up the menu bar, not to restart the app or validate event access.
    static func pollingUntilEnabled(completion: @escaping () -> Void) {
        guard enabled else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                pollingUntilEnabled(completion: completion)
            }
            return
        }
        completion()
    }

    /// Drag-to-authorize is a manual Settings flow. Request APIs would also leave
    /// a separate system consent alert open alongside our floating guide.
    static func openSettings() {
        NSWorkspace.shared
            .open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    struct Naming {
        let macOSMajorVersion: Int

        static var current: Self {
            Self(macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        }

        var settingsPaneKey: String {
            macOSMajorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
        }

        var formerNameKey: String? {
            macOSMajorVersion >= 27 ? "Accessibility" : nil
        }
    }
}
