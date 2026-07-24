// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ProcessEnvironmentTests: XCTestCase {
    func testUnitTestHostIsDetectedAsRunningTest() {
        XCTAssertTrue(ProcessEnvironment.isRunningTest)
    }

    func testProcessMetadataCacheDoesNotReuseValueForNewProcess() {
        let cache = ProcessMetadataCache<String>(countLimit: 16)
        let firstProcess = ProcessIdentity(pid: 42, startTimeSeconds: 100, startTimeMicroseconds: 1)
        let secondProcess = ProcessIdentity(pid: 42, startTimeSeconds: 200, startTimeMicroseconds: 2)

        XCTAssertEqual(cache.value(for: firstProcess) { "First" }, "First")
        XCTAssertEqual(cache.value(for: secondProcess) { "Second" }, "Second")
    }
}
