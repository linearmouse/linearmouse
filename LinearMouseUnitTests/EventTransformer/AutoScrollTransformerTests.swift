// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
@testable import LinearMouse
import XCTest

final class AutoScrollTransformerTests: XCTestCase {
    override func tearDown() {
        SettingsState.shared.endButtonMappingRecording()
        super.tearDown()
    }

    func testButtonMappingRecordingBypassesAutoScrollTrigger() throws {
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .mouse(2)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle, .hold],
            speed: 1
        )
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: CGPoint(x: -10_000, y: -10_000),
            mouseButton: .center
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        SettingsState.shared.beginButtonMappingRecording(sessionID: UUID())

        XCTAssertIdentical(
            transformer.transform(event, in: .init(device: nil)),
            event
        )
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testLogitechModifierMismatchAllowsLowerPriorityRecognizer() {
        let identity = LogitechControlIdentity(controlID: 0xC4)
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .logitechControl(identity)
        trigger.command = true
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.hold],
            speed: 1
        )

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(.init(
                device: nil,
                pid: nil,
                display: nil,
                mouseLocation: .zero,
                controlIdentity: identity,
                isPressed: true,
                modifierFlags: []
            )),
            .notHandled
        )
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testCancelingLostLogitechHoldStopsAutoScroll() {
        let identity = LogitechControlIdentity(controlID: 0xC4)
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .logitechControl(identity)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.hold],
            speed: 1
        )
        let context = LogitechEventContext(
            device: nil,
            pid: nil,
            display: nil,
            mouseLocation: .zero,
            controlIdentity: identity,
            isPressed: true,
            modifierFlags: []
        )

        XCTAssertEqual(transformer.handleLogitechControlEvent(context), .handled)
        XCTAssertTrue(transformer.isAutoscrollActive)

        XCTAssertTrue(transformer.cancelLogitechControlInteraction(context))
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testMatchesConfigurationDistinguishesActivateOverPressableElements() {
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .mouse(2)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle],
            speed: 1,
            activateOverPressableElements: true
        )

        XCTAssertTrue(transformer.matchesConfiguration(
            trigger: trigger,
            modes: [.toggle],
            speed: 1,
            activateOverPressableElements: true
        ))
        XCTAssertFalse(transformer.matchesConfiguration(
            trigger: trigger,
            modes: [.toggle],
            speed: 1,
            activateOverPressableElements: false
        ))
    }
}
