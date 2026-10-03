// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ProcessEnvironmentTests: XCTestCase {
    func testUnitTestHostIsDetectedAsRunningTest() {
        XCTAssertTrue(ProcessEnvironment.isRunningTest)
    }

    func testConfigurationStorageIsIsolatedFromTheUserProfile() throws {
        XCTAssertFalse(ProcessEnvironment.isRunningApp)
        let paths = ConfigurationState.shared.configurationPaths
        XCTAssertEqual(paths.count, 1)
        let path = try XCTUnwrap(paths.first)
        XCTAssertTrue(path.deletingLastPathComponent().lastPathComponent.hasPrefix("linearmouse-tests-"))
        XCTAssertEqual(path, ConfigurationState().configurationPath)
        if let expectedHome = ProcessInfo.processInfo.environment["LINEARMOUSE_EXPECTED_TEST_HOME"] {
            XCTAssertEqual(NSHomeDirectory(), expectedHome)
        }
    }

    func testProcessMetadataCacheDoesNotReuseValueForNewProcess() {
        let cache = ProcessMetadataCache<String>(countLimit: 16)
        let firstProcess = ProcessIdentity(pid: 42, startTimeSeconds: 100, startTimeMicroseconds: 1)
        let secondProcess = ProcessIdentity(pid: 42, startTimeSeconds: 200, startTimeMicroseconds: 2)

        XCTAssertEqual(cache.value(for: firstProcess) { "First" }, "First")
        XCTAssertEqual(cache.value(for: secondProcess) { "Second" }, "Second")
    }
}
