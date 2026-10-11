// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class SwipeConfigurationTests: XCTestCase {
    func testOldConfigurationsKeepDefaultDistanceAndDoNotLockPointer() throws {
        let configuration = try Configuration.load(from: #"{"schemes":[{"buttons":{}}]}"#)
        let swipe = configuration.matchScheme(withDeviceMatcher: nil).buttons.swipe
        XCTAssertEqual(swipe.effectiveThreshold, 50)
        XCTAssertFalse(ButtonMappingPolicy.configured(by: swipe).lockPointer)
        XCTAssertNil(configuration.schemes.first?.buttons.$swipe)
    }

    func testRoundTripAndFieldByFieldInheritance() throws {
        let source = #"""
        {"schemes":[
          {"buttons":{"swipe":{"threshold":50,"lockPointer":true}}},
          {"if":{"device":{"category":"trackpad"}},"buttons":{"swipe":{"threshold":20}}},
          {"if":{"device":{"category":"trackpad"},"app":"com.apple.Safari"},
           "buttons":{"swipe":{"lockPointer":false}}}
        ]}
        """#
        let configuration = try Configuration.load(from: source)
        let mouse = configuration.matchScheme(withDeviceMatcher: DeviceMatcher(category: .mouse)).buttons.swipe
        XCTAssertEqual(mouse.threshold, 50)
        XCTAssertTrue(try XCTUnwrap(mouse.lockPointer))
        let trackpad = configuration.matchScheme(withDeviceMatcher: DeviceMatcher(category: .trackpad)).buttons.swipe
        XCTAssertEqual(trackpad.threshold, 20)
        XCTAssertTrue(try XCTUnwrap(trackpad.lockPointer))
        let safari = configuration.matchScheme(
            withDeviceMatcher: DeviceMatcher(category: .trackpad), withApp: "com.apple.Safari"
        )
        .buttons
        .swipe
        XCTAssertEqual(safari.threshold, 20)
        XCTAssertFalse(try XCTUnwrap(safari.lockPointer))
        XCTAssertEqual(try Configuration.load(from: configuration.dump()), configuration)
    }

    func testThresholdClampsToSupportedRange() {
        for (input, expected) in [(-10.0, 10.0), (0, 10), (10, 10), (20.5, 20.5), (200, 200), (1000, 200)] {
            XCTAssertEqual(ButtonMappingPolicy.configured(by: .init(threshold: input)).swipeThreshold, expected)
        }
    }

    func testChangesAndRemovalInvalidateEventTransformers() {
        let original = Configuration(schemes: [Scheme()])
        for swipe in [Scheme.Buttons.Swipe(threshold: 20), .init(lockPointer: true), .init(lockPointer: false)] {
            var changed = original
            changed.schemes[0].buttons.swipe = swipe
            for (previous, current) in [(original, changed), (changed, original)] {
                let diff = ConfigurationDiff(previous: previous, current: current)
                XCTAssertTrue(diff.affectsEventTransformers)
                XCTAssertFalse(diff.affectsFocusFollowsMouse)
            }
        }
    }
}
