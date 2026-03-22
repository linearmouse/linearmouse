// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class DistanceModeTests: XCTestCase {
    func testAutoDistanceUsesByLinesMode() {
        XCTAssertEqual(Scheme.Scrolling.Distance.auto.mode, .byLines)
    }

    func testPixelDistanceUsesByPixelsMode() {
        XCTAssertEqual(Scheme.Scrolling.Distance.pixel(8).mode, .byPixels)
    }
}
