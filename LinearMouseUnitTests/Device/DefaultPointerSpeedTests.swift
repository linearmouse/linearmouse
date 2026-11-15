// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class DefaultPointerSpeedTests: XCTestCase {
    func testResolutionsInsideTheScaleAreUnchanged() {
        XCTAssertEqual(Device.defaultPointerSpeed(fromPointerResolution: 1200), 0, accuracy: 0.0001)
        XCTAssertEqual(Device.defaultPointerSpeed(fromPointerResolution: 40), 1, accuracy: 0.0001)
        XCTAssertEqual(
            Device.defaultPointerSpeed(fromPointerResolution: 400),
            Device.pointerSpeed(fromPointerResolution: 400),
            accuracy: 0.0001
        )
    }

    func testSlowerResolutionsThanTheScaleShowAsZero() {
        // A Magic Mouse can report a resolution above 1200, which converts to a negative speed.
        XCTAssertLessThan(Device.pointerSpeed(fromPointerResolution: 1600), 0)
        XCTAssertEqual(Device.defaultPointerSpeed(fromPointerResolution: 1600), 0)
        XCTAssertEqual(Device.defaultPointerSpeed(fromPointerResolution: 1995), 0)
    }

    func testFasterResolutionsThanTheScaleShowAsOne() {
        XCTAssertGreaterThan(Device.pointerSpeed(fromPointerResolution: 10), 1)
        XCTAssertEqual(Device.defaultPointerSpeed(fromPointerResolution: 10), 1)
    }
}
