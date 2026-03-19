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
        trigger.button = 4
        trigger.shift = true
        scheme.buttons.autoScroll.trigger = trigger

        Scheme().merge(into: &scheme)

        XCTAssertEqual(scheme.buttons.autoScroll.enabled, true)
        XCTAssertEqual(scheme.buttons.autoScroll.modes, [.hold])
        XCTAssertEqual(scheme.buttons.autoScroll.trigger?.button, 4)
        XCTAssertEqual(scheme.buttons.autoScroll.trigger?.modifierFlags.contains(.maskShift), true)
    }

    func testMergeAutoScrollPreservesInheritedFields() {
        var scheme = Scheme()
        scheme.buttons.autoScroll.enabled = true
        scheme.buttons.autoScroll.modes = [.toggle]
        scheme.buttons.autoScroll.speed = 1

        var trigger = Scheme.Buttons.Mapping()
        trigger.button = 2
        trigger.command = true
        scheme.buttons.autoScroll.trigger = trigger

        var override = Scheme()
        override.buttons.autoScroll.speed = 2
        override.buttons.autoScroll.modes = [.toggle, .hold]
        override.merge(into: &scheme)

        XCTAssertEqual(scheme.buttons.autoScroll.enabled, true)
        XCTAssertEqual(scheme.buttons.autoScroll.modes, [.toggle, .hold])
        XCTAssertEqual(scheme.buttons.autoScroll.speed, 2)
        XCTAssertEqual(scheme.buttons.autoScroll.trigger?.button, 2)
        XCTAssertEqual(scheme.buttons.autoScroll.trigger?.modifierFlags.contains(.maskCommand), true)
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
}
