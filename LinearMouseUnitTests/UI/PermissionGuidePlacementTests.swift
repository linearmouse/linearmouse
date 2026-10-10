// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class PermissionGuidePlacementTests: XCTestCase {
    func testFollowsSettingsMovementWhenThereIsRoom() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1200)
        let target = CGRect(x: 300, y: 600, width: 700, height: 500)
        let size = CGSize(width: 470, height: 180)
        let initial = PermissionGuidePlacement.frame(size: size, below: target, within: screen)
        let moved = PermissionGuidePlacement.frame(size: size, below: target.offsetBy(dx: 50, dy: -40), within: screen)
        XCTAssertEqual(moved.origin.x - initial.origin.x, 50)
        XCTAssertEqual(moved.origin.y - initial.origin.y, -40)
        XCTAssertEqual(initial.maxX, target.maxX)
        XCTAssertEqual(initial.maxY, target.minY - 6)
    }

    func testClampsToScreenWhenSettingsIsNearBottom() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let target = CGRect(x: 700, y: 100, width: 700, height: 700)
        let result = PermissionGuidePlacement.frame(
            size: .init(width: 470, height: 180),
            below: target,
            within: screen
        )
        XCTAssertEqual(result.minY, screen.minY + 12)
        XCTAssertTrue(screen.contains(result))
    }

    func testSmallScreenKeepsGuideVisible() {
        let screen = CGRect(x: 0, y: 30, width: 1024, height: 700)
        let target = CGRect(x: 100, y: 100, width: 700, height: 700)
        let result = PermissionGuidePlacement.frame(
            size: .init(width: 470, height: 180),
            below: target,
            within: screen
        )
        XCTAssertTrue(screen.contains(result))
        XCTAssertEqual(result.minY, screen.minY + 12)
    }

    func testDisplayWithNegativeOrigin() {
        let screen = CGRect(x: -1600, y: -300, width: 1600, height: 900)
        let target = CGRect(x: -1400, y: -200, width: 700, height: 700)
        let result = PermissionGuidePlacement.frame(
            size: .init(width: 470, height: 180),
            below: target,
            within: screen
        )
        XCTAssertTrue(screen.contains(result))
        XCTAssertEqual(result.maxX, target.maxX)
    }
}
