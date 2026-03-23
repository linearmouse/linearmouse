// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ConfigurationTests: XCTestCase {
    func testDump() throws {
        try print(Configuration(schemes: []).dump())
    }

    func testMergeScheme() {
        var scheme = Scheme()

        XCTAssertNil(scheme.$scrolling)

        Scheme(scrolling: .init(reverse: .init(vertical: true))).merge(into: &scheme)

        XCTAssertEqual(scheme.scrolling.reverse.vertical, true)
        XCTAssertNil(scheme.scrolling.reverse.horizontal)

        Scheme(scrolling: .init(reverse: .init(vertical: false, horizontal: true))).merge(into: &scheme)

        XCTAssertEqual(scheme.scrolling.reverse.vertical, false)
        XCTAssertEqual(scheme.scrolling.reverse.horizontal, true)

        Scheme(scrolling: .init(reverse: .init(vertical: true))).merge(into: &scheme)

        XCTAssertEqual(scheme.scrolling.reverse.vertical, true)
        XCTAssertEqual(scheme.scrolling.reverse.horizontal, true)
    }

    func testMergeAutoScroll() {
        var scheme = Scheme()
        scheme.buttons.autoScroll.enabled = true
        scheme.buttons.autoScroll.modes = [.hold]

        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .mouse(4)
        trigger.shift = true
        scheme.buttons.autoScroll.trigger = trigger

        Scheme().merge(into: &scheme)

        XCTAssertEqual(scheme.buttons.autoScroll.enabled, true)
        XCTAssertEqual(scheme.buttons.autoScroll.modes, [.hold])
        XCTAssertEqual(scheme.buttons.autoScroll.trigger?.button, .mouse(4))
        XCTAssertEqual(scheme.buttons.autoScroll.trigger?.modifierFlags.contains(.maskShift), true)
    }

    func testMergeAutoScrollPreservesInheritedFields() {
        var scheme = Scheme()
        scheme.buttons.autoScroll.enabled = true
        scheme.buttons.autoScroll.modes = [.toggle]
        scheme.buttons.autoScroll.speed = 1

        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .mouse(2)
        trigger.command = true
        scheme.buttons.autoScroll.trigger = trigger

        var override = Scheme()
        override.buttons.autoScroll.speed = 2
        override.buttons.autoScroll.modes = [.toggle, .hold]
        override.merge(into: &scheme)

        XCTAssertEqual(scheme.buttons.autoScroll.enabled, true)
        XCTAssertEqual(scheme.buttons.autoScroll.modes, [.toggle, .hold])
        XCTAssertEqual(scheme.buttons.autoScroll.speed, 2)
        XCTAssertEqual(scheme.buttons.autoScroll.trigger?.button, .mouse(2))
        XCTAssertEqual(scheme.buttons.autoScroll.trigger?.modifierFlags.contains(.maskCommand), true)
    }

    func testMergeAutoScrollAllowsDisablingInheritedSetting() {
        var scheme = Scheme()
        scheme.buttons.autoScroll.enabled = true
        scheme.buttons.autoScroll.modes = [.toggle]

        var override = Scheme()
        override.buttons.autoScroll.enabled = false
        override.merge(into: &scheme)

        XCTAssertEqual(scheme.buttons.autoScroll.enabled, false)
        XCTAssertEqual(scheme.buttons.autoScroll.modes, [.toggle])
    }

    func testMappingDecodesLegacyGenericModifierFlagsWithoutRawFlags() throws {
        let mapping = try JSONDecoder().decode(
            Scheme.Buttons.Mapping.self,
            from: XCTUnwrap(#"{"button":3,"command":true}"#.data(using: .utf8))
        )

        XCTAssertEqual(mapping.modifierFlags, [.maskCommand])
        XCTAssertTrue(mapping.command == true)
        XCTAssertFalse(mapping.shift == true)
    }

    func testMappingDecodesLegacyLogitechControlFieldIntoButton() throws {
        let mapping = try JSONDecoder().decode(
            Scheme.Buttons.Mapping.self,
            from: XCTUnwrap(
                #"{"logiButton":{"controlID":208,"logicalDeviceProductID":16478,"logicalDeviceSerialNumber":"ABC123"}}"#
                    .data(using: .utf8)
            )
        )

        XCTAssertEqual(
            mapping.button,
            .logitechControl(.init(controlID: 208, productID: 16_478, serialNumber: "ABC123"))
        )
    }

    func testMappingEncodesLogitechControlButtonAsTaggedStructure() throws {
        let mapping = Scheme.Buttons.Mapping(
            button: .logitechControl(.init(controlID: 208, productID: 16_478, serialNumber: "ABC123"))
        )

        let data = try JSONEncoder().encode(mapping)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let button = try XCTUnwrap(jsonObject["button"] as? [String: Any])

        XCTAssertEqual(button["kind"] as? String, "logitechControl")
        XCTAssertEqual(button["controlID"] as? Int, 208)
        XCTAssertEqual(button["productID"] as? Int, 16_478)
        XCTAssertEqual(button["serialNumber"] as? String, "ABC123")
    }

    func testLogitechControlButtonDecodesHexProductID() throws {
        let mapping = try JSONDecoder().decode(
            Scheme.Buttons.Mapping.self,
            from: XCTUnwrap(
                #"{"button":{"kind":"logitechControl","controlID":208,"productID":"0x405E"}}"#
                    .data(using: .utf8)
            )
        )

        XCTAssertEqual(
            mapping.button,
            .logitechControl(.init(controlID: 208, productID: 0x405E, serialNumber: nil))
        )
    }

    func testDecodeAutoScrollSingleMode() throws {
        let autoScroll = try JSONDecoder().decode(
            Scheme.Buttons.AutoScroll.self,
            from: XCTUnwrap(#"{"enabled":true,"mode":"hold"}"#.data(using: .utf8))
        )

        XCTAssertEqual(autoScroll.modes, [.hold])
        XCTAssertEqual(autoScroll.normalizedModes, [.hold])
    }

    func testDecodeAutoScrollMultipleModes() throws {
        let autoScroll = try JSONDecoder().decode(
            Scheme.Buttons.AutoScroll.self,
            from: XCTUnwrap(#"{"enabled":true,"mode":["toggle","hold"]}"#.data(using: .utf8))
        )

        XCTAssertEqual(autoScroll.modes, [.toggle, .hold])
        XCTAssertEqual(autoScroll.normalizedModes, [.toggle, .hold])
    }

    func testMergeSmoothedScrollingPreservesInheritedFields() {
        var scheme = Scheme(
            scrolling: .init(
                smoothed: .init(
                    vertical: .init(
                        preset: .natural,
                        response: Decimal(string: "0.45"),
                        speed: 1,
                        acceleration: Decimal(string: "1.2"),
                        inertia: Decimal(string: "0.65")
                    )
                )
            )
        )

        Scheme(
            scrolling: .init(
                smoothed: .init(
                    vertical: .init(
                        preset: .snappy,
                        inertia: 8
                    )
                )
            )
        ).merge(into: &scheme)

        XCTAssertEqual(scheme.scrolling.smoothed.vertical?.preset, .snappy)
        XCTAssertEqual(scheme.scrolling.smoothed.vertical?.response, Decimal(string: "0.45"))
        XCTAssertEqual(scheme.scrolling.smoothed.vertical?.speed, 1)
        XCTAssertEqual(scheme.scrolling.smoothed.vertical?.acceleration, Decimal(string: "1.2"))
        XCTAssertEqual(scheme.scrolling.smoothed.vertical?.inertia, 8)
    }
}
