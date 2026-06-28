// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
@testable import LinearMouse
import XCTest

private let testLogitechControlID = 0x0001
private let testGestureThreshold = 10.0
private let testGestureDeadZone = 40.0
private let testGestureCooldownMs = 500

private func logitechContext(
    pressed: Bool,
    modifierFlags: CGEventFlags = []
) -> LogitechEventContext {
    .init(
        device: nil,
        pid: nil,
        display: nil,
        mouseLocation: .zero,
        controlIdentity: .init(controlID: testLogitechControlID),
        isPressed: pressed,
        modifierFlags: modifierFlags
    )
}

private func makeLogitechGestureTransformer(
    trigger: Scheme.Buttons.Mapping = .init(
        button: .logitechControl(.init(controlID: testLogitechControlID))
    )
) -> GestureButtonTransformer {
    GestureButtonTransformer(
        trigger: trigger,
        threshold: testGestureThreshold,
        deadZone: testGestureDeadZone,
        cooldownMs: testGestureCooldownMs,
        actions: .init(right: Scheme.Buttons.Gesture.GestureAction.none)
    )
}

private func makeMouseMovedEvent(deltaX: Double, deltaY: Double = 0) throws -> CGEvent {
    let event = try XCTUnwrap(CGEvent(
        mouseEventSource: nil,
        mouseType: .mouseMoved,
        mouseCursorPosition: .zero,
        mouseButton: .center
    ))
    event.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
    event.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
    return event
}

final class GestureButtonTransformerTests: XCTestCase {
    func testLogitechControlClickAllowsSyntheticFallbackWhenGestureDoesNotTrigger() {
        let transformer = makeLogitechGestureTransformer()

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitechContext(pressed: true)),
            .handledDeferringSyntheticFallback
        )
        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitechContext(pressed: false)),
            .notHandled
        )
    }

    func testLogitechControlModifierMismatchAllowsSyntheticFallback() {
        let transformer = makeLogitechGestureTransformer(trigger: .init(
            button: .logitechControl(.init(controlID: testLogitechControlID)),
            shift: true
        ))

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitechContext(pressed: true)),
            .notHandled
        )
    }

    func testLogitechControlGestureSuppressesSyntheticFallbackForCleanupRelease() throws {
        let transformer = makeLogitechGestureTransformer()

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitechContext(pressed: true)),
            .handledDeferringSyntheticFallback
        )

        XCTAssertNil(try transformer.transform(
            makeMouseMovedEvent(deltaX: testGestureThreshold),
            in: EventTransformerContext(device: nil)
        ))
        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitechContext(pressed: false)),
            .handled
        )
    }

    func testLogitechControlCooldownConsumesAdditionalPressesAfterCleanupRelease() throws {
        let transformer = makeLogitechGestureTransformer()

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitechContext(pressed: true)),
            .handledDeferringSyntheticFallback
        )
        XCTAssertNil(try transformer.transform(
            makeMouseMovedEvent(deltaX: testGestureThreshold),
            in: EventTransformerContext(device: nil)
        ))
        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitechContext(pressed: false)),
            .handled
        )
        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitechContext(pressed: true)),
            .handled
        )
    }
}
