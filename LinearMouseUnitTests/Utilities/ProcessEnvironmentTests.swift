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

    func testXDGConfigHomeAcceptsAbsolutePath() throws {
        let url = try XCTUnwrap(
            ProcessEnvironment.xdgConfigHome(from: ["XDG_CONFIG_HOME": "/Users/example/Library/config"])
        )

        XCTAssertEqual(url.path, "/Users/example/Library/config")
    }

    func testXDGConfigHomeIsNilWhenUnset() {
        XCTAssertNil(ProcessEnvironment.xdgConfigHome(from: [:]))
    }

    func testXDGConfigHomeIsNilWhenEmpty() {
        XCTAssertNil(ProcessEnvironment.xdgConfigHome(from: ["XDG_CONFIG_HOME": ""]))
    }

    func testXDGConfigHomeIgnoresRelativePath() {
        // The XDG Base Directory Specification requires relative paths to be ignored.
        XCTAssertNil(ProcessEnvironment.xdgConfigHome(from: ["XDG_CONFIG_HOME": "config"]))
        XCTAssertNil(ProcessEnvironment.xdgConfigHome(from: ["XDG_CONFIG_HOME": "./config"]))
    }

    func testXDGConfigHomeIgnoresUnexpandedTilde() {
        // An unexpanded tilde is not an absolute path, so it is not a usable value.
        XCTAssertNil(ProcessEnvironment.xdgConfigHome(from: ["XDG_CONFIG_HOME": "~/config"]))
    }

    func testXDGConfigHomeResolvesChildPathsWhenDirectoryDoesNotExist() throws {
        // A directory that does not exist yet must still behave as a directory, otherwise
        // URL(fileURLWithPath:relativeTo:) resolves child paths against its parent.
        let base = "/Users/example/linearmouse-does-not-exist-\(UUID().uuidString)/config"
        let url = try XCTUnwrap(ProcessEnvironment.xdgConfigHome(from: ["XDG_CONFIG_HOME": base]))
        let child = URL(fileURLWithPath: "linearmouse/linearmouse.json", relativeTo: url)

        XCTAssertEqual(child.path, base + "/linearmouse/linearmouse.json")
    }

    func testXDGConfigHomeStandardizesPath() throws {
        let url = try XCTUnwrap(
            ProcessEnvironment.xdgConfigHome(from: ["XDG_CONFIG_HOME": "/Users/example/Library/../config/"])
        )

        XCTAssertEqual(url.path, "/Users/example/config")
    }
}
