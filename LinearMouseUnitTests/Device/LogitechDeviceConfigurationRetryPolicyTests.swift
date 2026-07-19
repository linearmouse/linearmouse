// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class LogitechDeviceConfigurationRetryPolicyTests: XCTestCase {
    func testUsesTwoBackoffRetries() {
        XCTAssertEqual(LogitechDeviceConfigurationRetryPolicy.delay(afterAttempt: 1), 1)
        XCTAssertEqual(LogitechDeviceConfigurationRetryPolicy.delay(afterAttempt: 2), 3)
        XCTAssertNil(LogitechDeviceConfigurationRetryPolicy.delay(afterAttempt: 3))
    }

    func testRejectsInvalidAttemptNumber() {
        XCTAssertNil(LogitechDeviceConfigurationRetryPolicy.delay(afterAttempt: 0))
        XCTAssertNil(LogitechDeviceConfigurationRetryPolicy.delay(afterAttempt: -1))
    }
}
