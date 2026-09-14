// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import DockKit
import Foundation
import XCTest

final class DockKitTests: XCTestCase {
    private func skipUnlessIntegrationEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1",
            "Set RUN_INTEGRATION_TESTS=1 to run DockKit integration tests that activate system UI."
        )
    }

    func testLaunchpad() throws {
        try skipUnlessIntegrationEnabled()
        launchpad()
    }

    func testMissionControl() throws {
        try skipUnlessIntegrationEnabled()
        missionControl()
    }

    func testShowDesktop() throws {
        try skipUnlessIntegrationEnabled()
        showDesktop()
    }

    func testAppExpose() throws {
        try skipUnlessIntegrationEnabled()
        appExpose()
    }
}
