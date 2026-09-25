// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
@testable import LinearMouse
import XCTest

final class PointerRedirectsToScrollTriggerTransformerTests: XCTestCase {
    private var redirectedEvents = [CGEvent]()

    override func setUp() {
        super.setUp()
        redirectedEvents = []
    }

    override func tearDown() {
        SettingsState.shared.endButtonMappingRecording()
        super.tearDown()
    }

    private func makeTransformer(
        _ trigger: Scheme.Trigger = .init(input: .button(.mouse(3)))
    ) throws -> PointerRedirectsToScrollTriggerTransformer {
        try XCTUnwrap(PointerRedirectsToScrollTriggerTransformer(trigger: trigger) { [weak self] event in
            self?.redirectedEvents.append(event)
        })
    }

    private func transform(
        _ transformer: PointerRedirectsToScrollTriggerTransformer,
        _ event: CGEvent
    ) -> CGEvent? {
        transformer.transform(event, in: .init(device: nil))
    }

    private func buttonEvent(
        _ type: CGEventType,
        button: Int,
        flags: CGEventFlags = []
    ) throws -> CGEvent {
        let mouseButton = try XCTUnwrap(CGMouseButton(rawValue: UInt32(button)))
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: .zero,
            mouseButton: mouseButton
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        event.flags = flags
        return event
    }

    private func movedEvent(deltaX: Double = 5, deltaY: Double = 7) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: .zero,
            mouseButton: .left
        ))
        event.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
        event.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
        return event
    }

    func testRejectsTriggersThatCannotBeHeld() {
        XCTAssertNil(PointerRedirectsToScrollTriggerTransformer(trigger: .init(input: .button(.mouse(0)))))
        XCTAssertNil(PointerRedirectsToScrollTriggerTransformer(trigger: .init(input: .wheel(.down))))
        XCTAssertNil(PointerRedirectsToScrollTriggerTransformer(
            trigger: .init(input: .button(.logitechControl(.init(controlID: 0x00C3))))
        ))
    }

    func testMovementPassesThroughWhileReleased() throws {
        let transformer = try makeTransformer()

        XCTAssertNotNil(try transform(transformer, movedEvent()))
        XCTAssertNotNil(try transform(transformer, buttonEvent(.otherMouseDragged, button: 2)))
        XCTAssertTrue(redirectedEvents.isEmpty)
        XCTAssertFalse(transformer.hasActiveInteraction)
    }

    func testRedirectsMovementOnlyWhileTriggerIsHeld() throws {
        let transformer = try makeTransformer()

        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseDown, button: 3)))
        XCTAssertTrue(transformer.hasActiveInteraction)

        let drag = try buttonEvent(.otherMouseDragged, button: 3)
        drag.setDoubleValueField(.mouseEventDeltaX, value: 4)
        drag.setDoubleValueField(.mouseEventDeltaY, value: -6)
        XCTAssertNil(transform(transformer, drag))
        XCTAssertNil(try transform(transformer, movedEvent()))
        XCTAssertEqual(redirectedEvents.count, 2)
        XCTAssertEqual(redirectedEvents.first?.getDoubleValueField(.mouseEventDeltaX), 4)
        XCTAssertEqual(redirectedEvents.first?.getDoubleValueField(.mouseEventDeltaY), -6)

        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 3)))
        XCTAssertFalse(transformer.hasActiveInteraction)

        XCTAssertNotNil(try transform(transformer, movedEvent()))
        XCTAssertEqual(redirectedEvents.count, 2)
    }

    func testOtherButtonsPassThroughWhileTriggerIsHeld() throws {
        let transformer = try makeTransformer()

        XCTAssertNotNil(try transform(transformer, buttonEvent(.otherMouseDown, button: 4)))
        XCTAssertNotNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 4)))
        XCTAssertFalse(transformer.hasActiveInteraction)

        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseDown, button: 3)))
        XCTAssertNotNil(try transform(transformer, buttonEvent(.leftMouseDown, button: 0)))
        XCTAssertNotNil(try transform(transformer, buttonEvent(.leftMouseUp, button: 0)))
        XCTAssertTrue(transformer.hasActiveInteraction)

        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 3)))
        XCTAssertFalse(transformer.hasActiveInteraction)
    }

    func testModifiersMustMatchWhenTheTriggerIsPressed() throws {
        let transformer = try makeTransformer(.init(input: .button(.mouse(3)), modifiers: [.option]))

        XCTAssertNotNil(try transform(transformer, buttonEvent(.otherMouseDown, button: 3)))
        XCTAssertNotNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 3)))
        XCTAssertNotNil(try transform(
            transformer,
            buttonEvent(.otherMouseDown, button: 3, flags: [.maskAlternate, .maskShift])
        ))
        XCTAssertNotNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 3)))
        XCTAssertFalse(transformer.hasActiveInteraction)

        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseDown, button: 3, flags: .maskAlternate)))
        XCTAssertTrue(transformer.hasActiveInteraction)

        // Releasing the modifier while the button is held keeps redirecting.
        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseDragged, button: 3)))
        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 3)))
        XCTAssertEqual(redirectedEvents.count, 1)
    }

    func testPrimaryButtonWithModifierCanBeTheTrigger() throws {
        let transformer = try makeTransformer(.init(input: .button(.mouse(0)), modifiers: [.command]))

        XCTAssertNotNil(try transform(transformer, buttonEvent(.leftMouseDown, button: 0)))
        XCTAssertNotNil(try transform(transformer, buttonEvent(.leftMouseUp, button: 0)))

        XCTAssertNil(try transform(transformer, buttonEvent(.leftMouseDown, button: 0, flags: .maskCommand)))
        XCTAssertNil(try transform(transformer, buttonEvent(.leftMouseDragged, button: 0)))
        XCTAssertNil(try transform(transformer, buttonEvent(.leftMouseUp, button: 0)))
        XCTAssertEqual(redirectedEvents.count, 1)
    }

    func testBypassesTriggerWhileRecording() throws {
        let transformer = try makeTransformer()
        SettingsState.shared.beginButtonMappingRecording(sessionID: UUID())

        XCTAssertNotNil(try transform(transformer, buttonEvent(.otherMouseDown, button: 3)))
        XCTAssertNotNil(try transform(transformer, buttonEvent(.otherMouseDragged, button: 3)))
        XCTAssertNotNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 3)))
        XCTAssertTrue(redirectedEvents.isEmpty)
    }

    func testDeactivateReleasesTheHeldTrigger() throws {
        let transformer = try makeTransformer()

        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseDown, button: 3)))
        transformer.deactivate()

        XCTAssertFalse(transformer.hasActiveInteraction)
        XCTAssertNotNil(try transform(transformer, movedEvent()))
        XCTAssertTrue(redirectedEvents.isEmpty)
    }
}
