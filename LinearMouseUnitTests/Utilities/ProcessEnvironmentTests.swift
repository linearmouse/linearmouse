// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ProcessEnvironmentTests: XCTestCase {
    func testUnitTestHostIsDetectedAsRunningTest() {
        XCTAssertTrue(ProcessEnvironment.isRunningTest)
    }
}
