// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ClickDebouncingTests: XCTestCase {
    func testLegacyConfigurationWithoutModeStillDecodes() throws {
        let clickDebouncing = try JSONDecoder().decode(
            Scheme.Buttons.ClickDebouncing.self,
            from: Data(#"{"timeout":50,"resetTimerOnMouseUp":true,"buttons":[0,1]}"#.utf8)
        )

        XCTAssertNil(clickDebouncing.mode)
        XCTAssertEqual(clickDebouncing.timeout, 50)
        XCTAssertTrue(try XCTUnwrap(clickDebouncing.resetTimerOnMouseUp))
        XCTAssertEqual(clickDebouncing.buttons, [.left, .right])
    }

    func testLibinputModeDecodes() throws {
        let clickDebouncing = try JSONDecoder().decode(
            Scheme.Buttons.ClickDebouncing.self,
            from: Data(#"{"mode":"libinput","timeout":25,"buttons":[0]}"#.utf8)
        )

        XCTAssertEqual(clickDebouncing.mode, .libinput)
        XCTAssertEqual(clickDebouncing.timeout, 25)
        XCTAssertEqual(clickDebouncing.buttons, [.left])
    }

    func testModeEncodesAsStableConfigurationValue() throws {
        var clickDebouncing = Scheme.Buttons.ClickDebouncing()
        clickDebouncing.mode = .libinput
        clickDebouncing.timeout = 25

        let data = try JSONEncoder().encode(clickDebouncing)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["mode"] as? String, "libinput")
        XCTAssertEqual(object["timeout"] as? Int, 25)
    }

    func testModeOverridePreservesInheritedClickDebouncingSettings() throws {
        var mergedScheme = Scheme()
        mergedScheme.buttons.clickDebouncing.timeout = 50
        mergedScheme.buttons.clickDebouncing.resetTimerOnMouseUp = true
        mergedScheme.buttons.clickDebouncing.buttons = [.left, .right]

        var overrideScheme = Scheme()
        overrideScheme.buttons.clickDebouncing.mode = .libinput
        overrideScheme.merge(into: &mergedScheme)

        XCTAssertEqual(mergedScheme.buttons.clickDebouncing.mode, .libinput)
        XCTAssertEqual(mergedScheme.buttons.clickDebouncing.timeout, 50)
        XCTAssertTrue(try XCTUnwrap(mergedScheme.buttons.clickDebouncing.resetTimerOnMouseUp))
        XCTAssertEqual(mergedScheme.buttons.clickDebouncing.buttons, [.left, .right])
    }
}
