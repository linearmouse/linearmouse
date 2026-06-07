// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Foundation

extension Scheme {
    struct If: Codable, Equatable {
        var device: DeviceMatcher?

        var app: String?
        var parentApp: String?
        var groupApp: String?

        // Match by executable instead of app bundle
        var processName: String?
        var processPath: String?

        var display: String?
    }
}

extension Scheme.If {
    init(matchContext context: Scheme.MatchContext) {
        self.init(
            device: context.device,
            app: context.app,
            parentApp: context.parentApp,
            groupApp: context.groupApp,
            processName: context.processName,
            processPath: context.processPath,
            display: context.display
        )
    }

    func isSatisfied(in context: Scheme.MatchContext) -> Bool {
        if let device {
            guard let targetDevice = context.device else {
                return false
            }

            guard device.isSatisfied(by: targetDevice) else {
                return false
            }
        }

        if let app {
            guard app == context.app else {
                return false
            }
        }

        if let parentApp {
            guard parentApp == context.parentApp else {
                return false
            }
        }

        if let groupApp {
            guard groupApp == context.groupApp else {
                return false
            }
        }

        if let processName {
            guard processName == context.processName else {
                return false
            }
        }

        if let processPath {
            guard processPath == context.processPath else {
                return false
            }
        }

        if let display {
            guard let targetDisplay = context.display else {
                return false
            }

            guard display == targetDisplay else {
                return false
            }
        }

        return true
    }

    func isSatisfied(
        withDevice targetDevice: Device? = nil,
        withApp targetApp: String? = nil,
        withParentApp targetParentApp: String?,
        withGroupApp targetGroupApp: String?,
        withDisplay targetDisplay: String? = nil,
        withProcessName targetProcessName: String? = nil,
        withProcessPath targetProcessPath: String? = nil
    ) -> Bool {
        isSatisfied(
            in: Scheme.MatchContext(
                device: targetDevice,
                app: targetApp,
                parentApp: targetParentApp,
                groupApp: targetGroupApp,
                display: targetDisplay,
                processName: targetProcessName,
                processPath: targetProcessPath
            )
        )
    }

    func isSatisfied(
        withDeviceMatcher targetDeviceMatcher: DeviceMatcher? = nil,
        withApp targetApp: String? = nil,
        withParentApp targetParentApp: String?,
        withGroupApp targetGroupApp: String?,
        withDisplay targetDisplay: String? = nil,
        withProcessName targetProcessName: String? = nil,
        withProcessPath targetProcessPath: String? = nil
    ) -> Bool {
        isSatisfied(
            in: Scheme.MatchContext(
                deviceMatcher: targetDeviceMatcher,
                app: targetApp,
                parentApp: targetParentApp,
                groupApp: targetGroupApp,
                display: targetDisplay,
                processName: targetProcessName,
                processPath: targetProcessPath
            )
        )
    }
}
