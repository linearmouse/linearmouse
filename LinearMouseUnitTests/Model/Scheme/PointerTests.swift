// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class PointerTests: XCTestCase {
    func testDecodeRedirectsToScrollTrigger() throws {
        let pointer = try JSONDecoder().decode(
            Scheme.Pointer.self,
            from: Data(
                #"{"redirectsToScroll":true,"redirectsToScrollTrigger":{"input":{"button":3},"modifiers":["option"]}}"#
                    .utf8
            )
        )

        XCTAssertTrue(try XCTUnwrap(pointer.redirectsToScroll))
        XCTAssertEqual(
            pointer.redirectsToScrollTrigger,
            Scheme.Trigger(input: .button(.mouse(3)), modifiers: [.option])
        )
    }

    func testRedirectsToScrollTriggerRoundTrips() throws {
        var pointer = Scheme.Pointer()
        pointer.redirectsToScroll = true
        pointer.redirectsToScrollTrigger = .init(input: .button(.mouse(4)), modifiers: [.command, .shift])

        let data = try JSONEncoder().encode(pointer)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let trigger = try XCTUnwrap(json["redirectsToScrollTrigger"] as? [String: Any])
        XCTAssertEqual((trigger["input"] as? [String: Any])?["button"] as? Int, 4)
        XCTAssertEqual(trigger["modifiers"] as? [String], ["command", "shift"])

        XCTAssertEqual(try JSONDecoder().decode(Scheme.Pointer.self, from: data), pointer)
    }

    func testRedirectsToScrollWithoutTriggerOmitsField() throws {
        var pointer = Scheme.Pointer()
        pointer.redirectsToScroll = true

        let data = try JSONEncoder().encode(pointer)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["redirectsToScroll"] as? Bool, true)
        XCTAssertNil(json["redirectsToScrollTrigger"])
    }

    func testMappingTriggerIsTheSharedTrigger() throws {
        let json = #"{"input":{"button":2},"whileHeld":[1],"modifiers":["control"]}"#
        let mappingTrigger = try JSONDecoder().decode(
            Scheme.Buttons.Mapping.Trigger.self,
            from: Data(json.utf8)
        )
        let sharedTrigger: Scheme.Trigger = mappingTrigger

        XCTAssertEqual(sharedTrigger.input, .button(.mouse(2)))
        XCTAssertEqual(sharedTrigger.whileHeld, [.mouse(1)])
        XCTAssertEqual(sharedTrigger.modifierFlags, .maskControl)
    }

    func testMergeRedirectsToScrollTrigger() {
        var pointer = Scheme.Pointer()
        pointer.redirectsToScroll = true
        pointer.redirectsToScrollTrigger = .init(input: .button(.mouse(3)))

        Scheme.Pointer().merge(into: &pointer)
        XCTAssertEqual(pointer.redirectsToScrollTrigger, .init(input: .button(.mouse(3))))

        var override = Scheme.Pointer()
        override.redirectsToScrollTrigger = .init(input: .button(.mouse(4)), modifiers: [.option])
        override.merge(into: &pointer)

        XCTAssertTrue(try XCTUnwrap(pointer.redirectsToScroll))
        XCTAssertEqual(pointer.redirectsToScrollTrigger, .init(input: .button(.mouse(4)), modifiers: [.option]))
    }

    func testRedirectsToScrollTriggerValidity() {
        XCTAssertTrue(Scheme.Trigger(input: .button(.mouse(2))).isValidRedirectsToScrollTrigger)
        XCTAssertTrue(Scheme.Trigger(input: .button(.mouse(1))).isValidRedirectsToScrollTrigger)
        XCTAssertTrue(
            Scheme.Trigger(input: .button(.mouse(3)), modifiers: [.option]).isValidRedirectsToScrollTrigger
        )
        XCTAssertTrue(
            Scheme.Trigger(input: .button(.mouse(0)), modifiers: [.command]).isValidRedirectsToScrollTrigger
        )

        XCTAssertFalse(Scheme.Trigger(input: .button(.mouse(0))).isValidRedirectsToScrollTrigger)
        XCTAssertFalse(Scheme.Trigger(input: .wheel(.up)).isValidRedirectsToScrollTrigger)
        XCTAssertFalse(
            Scheme.Trigger(input: .button(.logitechControl(.init(controlID: 0x00C3))))
                .isValidRedirectsToScrollTrigger
        )
        XCTAssertFalse(
            Scheme.Trigger(input: .button(.mouse(3)), simultaneous: [.mouse(4)]).isValidRedirectsToScrollTrigger
        )
        XCTAssertFalse(
            Scheme.Trigger(input: .button(.mouse(3)), whileHeld: [.mouse(1)]).isValidRedirectsToScrollTrigger
        )
    }
}
