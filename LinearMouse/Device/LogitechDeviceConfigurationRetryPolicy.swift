// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

enum LogitechDeviceConfigurationRetryPolicy {
    private static let retryDelays: [TimeInterval] = [1, 3]

    static func delay(afterAttempt attempt: Int) -> TimeInterval? {
        guard attempt > 0, retryDelays.indices.contains(attempt - 1) else {
            return nil
        }

        return retryDelays[attempt - 1]
    }
}
