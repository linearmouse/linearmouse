// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class PermissionNamingTests: XCTestCase {
    func testEarlierSystemsUseAccessibilityWithoutFootnoteOrMarker() {
        for version in [10, 11, 12, 13, 14, 15, 26] {
            let naming = AccessibilityPermission.Naming(macOSMajorVersion: version)
            XCTAssertEqual(naming.settingsPaneKey, "Accessibility")
            XCTAssertNil(naming.formerNameKey)
        }
    }

    func testRenamedPaneIncludesFormerSystemNameStartingWithMacOS27() {
        for version in [27, 28] {
            let naming = AccessibilityPermission.Naming(macOSMajorVersion: version)
            XCTAssertEqual(naming.settingsPaneKey, "Device Control and Data Access")
            XCTAssertEqual(naming.formerNameKey, "Accessibility")
        }
    }
}
