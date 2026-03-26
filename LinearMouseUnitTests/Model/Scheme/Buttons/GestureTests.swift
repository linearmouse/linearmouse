// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class GestureTests: XCTestCase {
    // MARK: - Legacy "button" → "trigger" migration

    func testDecodeLegacyButtonField() throws {
        let gesture = try JSONDecoder().decode(
            Scheme.Buttons.Gesture.self,
            from: XCTUnwrap(#"{"button":2,"threshold":60}"#.data(using: .utf8))
        )

        XCTAssertEqual(gesture.trigger?.button, .mouse(2))
        XCTAssertEqual(gesture.threshold, 60)
    }

    func testDecodeLegacyButtonFieldWithEnabledTrue() throws {
        let gesture = try JSONDecoder().decode(
            Scheme.Buttons.Gesture.self,
            from: XCTUnwrap(#"{"enabled":true,"button":2}"#.data(using: .utf8))
        )

        XCTAssertEqual(gesture.trigger?.button, .mouse(2))
    }

    func testDecodeLegacyButtonFieldWithEnabledFalse() throws {
        let gesture = try JSONDecoder().decode(
            Scheme.Buttons.Gesture.self,
            from: XCTUnwrap(#"{"enabled":false,"button":2}"#.data(using: .utf8))
        )

        XCTAssertEqual(gesture.enabled, false)
        XCTAssertEqual(gesture.trigger?.button, .mouse(2), "button should still migrate even when disabled")
    }

    func testDecodeLegacyEnabledFalseWithTrigger() throws {
        let gesture = try JSONDecoder().decode(
            Scheme.Buttons.Gesture.self,
            from: XCTUnwrap(
                #"{"enabled":false,"trigger":{"button":2}}"#.data(using: .utf8)
            )
        )

        XCTAssertEqual(gesture.enabled, false)
        XCTAssertNotNil(gesture.trigger, "trigger should be preserved even when disabled")
    }

    func testDecodeTriggerTakesPriorityOverLegacyButton() throws {
        let gesture = try JSONDecoder().decode(
            Scheme.Buttons.Gesture.self,
            from: XCTUnwrap(
                #"{"button":3,"trigger":{"button":4}}"#.data(using: .utf8)
            )
        )

        XCTAssertEqual(gesture.trigger?.button, .mouse(4), "trigger should take priority over legacy button")
    }

    func testDecodeNeitherButtonNorTrigger() throws {
        let gesture = try JSONDecoder().decode(
            Scheme.Buttons.Gesture.self,
            from: XCTUnwrap(#"{"threshold":80}"#.data(using: .utf8))
        )

        XCTAssertNil(gesture.trigger)
        XCTAssertEqual(gesture.threshold, 80)
    }

    // MARK: - Encoding

    func testEncodeWritesEnabledButNotLegacyButton() throws {
        var gesture = Scheme.Buttons.Gesture()
        gesture.enabled = true
        var mapping = Scheme.Buttons.Mapping()
        mapping.button = .mouse(2)
        gesture.trigger = mapping
        gesture.threshold = 50

        let data = try JSONEncoder().encode(gesture)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(jsonObject["enabled"] as? Bool, true)
        XCTAssertNil(jsonObject["button"], "legacy button should not be encoded")
        XCTAssertNotNil(jsonObject["trigger"])
        XCTAssertEqual(jsonObject["threshold"] as? Int, 50)
    }

    // MARK: - Round-trip

    func testRoundTrip() throws {
        var gesture = Scheme.Buttons.Gesture()
        var mapping = Scheme.Buttons.Mapping()
        mapping.button = .mouse(3)
        mapping.shift = true
        gesture.trigger = mapping
        gesture.threshold = 70
        gesture.deadZone = 30
        gesture.cooldownMs = 300
        gesture.actions.left = .spaceLeft
        gesture.actions.right = .spaceRight

        let data = try JSONEncoder().encode(gesture)
        let decoded = try JSONDecoder().decode(Scheme.Buttons.Gesture.self, from: data)

        XCTAssertEqual(decoded.trigger?.button, .mouse(3))
        XCTAssertEqual(decoded.trigger?.modifierFlags.contains(.maskShift), true)
        XCTAssertEqual(decoded.threshold, 70)
        XCTAssertEqual(decoded.deadZone, 30)
        XCTAssertEqual(decoded.cooldownMs, 300)
        XCTAssertEqual(decoded.actions.left, .spaceLeft)
        XCTAssertEqual(decoded.actions.right, .spaceRight)
    }

    func testLegacyRoundTripMigrates() throws {
        // Decode from legacy format
        let gesture = try JSONDecoder().decode(
            Scheme.Buttons.Gesture.self,
            from: XCTUnwrap(#"{"enabled":true,"button":2,"threshold":50}"#.data(using: .utf8))
        )

        // Encode (should write enabled+trigger, not legacy button)
        let data = try JSONEncoder().encode(gesture)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(jsonObject["enabled"] as? Bool, true)
        XCTAssertNil(jsonObject["button"])
        XCTAssertNotNil(jsonObject["trigger"])

        // Re-decode
        let decoded = try JSONDecoder().decode(Scheme.Buttons.Gesture.self, from: data)
        XCTAssertEqual(decoded.trigger?.button, .mouse(2))
        XCTAssertEqual(decoded.threshold, 50)
    }
}
