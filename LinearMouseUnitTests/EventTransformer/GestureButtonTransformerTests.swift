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
    ),
    deadZone: Double = testGestureDeadZone,
    cooldownMs: Int = testGestureCooldownMs
) -> GestureButtonTransformer {
    GestureButtonTransformer(
        trigger: trigger,
        threshold: testGestureThreshold,
        deadZone: deadZone,
        cooldownMs: cooldownMs,
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

private func makeMouseButtonEvent(
    type: CGEventType,
    button: CGMouseButton,
    deltaX: Double = 0
) throws -> CGEvent {
    let event = try XCTUnwrap(CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: .zero,
        mouseButton: button
    ))
    event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
    event.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
    return event
}

final class GestureButtonTransformerTests: XCTestCase {
    override func tearDown() {
        SettingsState.shared.endButtonMappingRecording()
        super.tearDown()
    }

    func testStandaloneMouseGestureBypassesNewInteractionsWhileRecording() throws {
        let button = try XCTUnwrap(CGMouseButton(rawValue: 4))
        let transformer = GestureButtonTransformer(
            trigger: .init(button: .mouse(4)),
            threshold: testGestureThreshold,
            deadZone: testGestureDeadZone,
            cooldownMs: testGestureCooldownMs,
            actions: .init(right: .some(.none))
        )
        SettingsState.shared.beginButtonMappingRecording(sessionID: UUID())

        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(type: .otherMouseDown, button: button),
            in: .init(device: nil)
        ))
        XCTAssertNotNil(try transformer.transform(
            makeMouseButtonEvent(type: .otherMouseDragged, button: button, deltaX: testGestureThreshold),
            in: .init(device: nil)
        ))
        XCTAssertFalse(transformer.hasActiveInteraction)
    }

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

    func testLogitechGestureKeepsReleaseAfterCooldownExpires() throws {
        let transformer = makeLogitechGestureTransformer(cooldownMs: 0)

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

    func testZeroDeadZoneAcceptsPerfectlyAxialGesture() throws {
        // deadZone 0 is valid (`@minimum 0`, default 40) and must mean "only
        // perfectly axial gestures are accepted", not "all gestures disabled".
        let transformer = makeLogitechGestureTransformer(deadZone: 0)

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitechContext(pressed: true)),
            .handledDeferringSyntheticFallback
        )
        // Perfectly axial horizontal drag: deltaX reaches the threshold, deltaY
        // is exactly 0. With deadZone == 0 this MUST be detected as a gesture,
        // consuming the mouseMoved event (transform returns nil).
        XCTAssertNil(try transformer.transform(
            makeMouseMovedEvent(deltaX: testGestureThreshold, deltaY: 0),
            in: EventTransformerContext(device: nil)
        ))
    }

    func testZeroDeadZoneRejectsOffAxisGesture() throws {
        let transformer = makeLogitechGestureTransformer(deadZone: 0)

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitechContext(pressed: true)),
            .handledDeferringSyntheticFallback
        )
        // Off-axis horizontal drag: deltaY == 5 exceeds the 0 dead zone, so the
        // gesture is rejected and the mouseMoved event passes through (transform
        // returns the non-nil event).
        XCTAssertNotNil(try transformer.transform(
            makeMouseMovedEvent(deltaX: testGestureThreshold, deltaY: 5),
            in: EventTransformerContext(device: nil)
        ))
    }
}
