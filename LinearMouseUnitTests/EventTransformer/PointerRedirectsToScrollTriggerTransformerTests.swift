// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
@testable import LinearMouse
import XCTest

final class PointerRedirectsToScrollTriggerTransformerTests: XCTestCase {
    private var redirectedEvents = [CGEvent]()
    private var sentEvents = [CGEvent]()
    private var warpedPoints = [CGPoint]()
    private var now: UInt64 = 0

    override func setUp() {
        super.setUp()
        redirectedEvents = []
        sentEvents = []
        warpedPoints = []
        now = 0
    }

    override func tearDown() {
        SettingsState.shared.endButtonMappingRecording()
        super.tearDown()
    }

    private func makeTransformer(
        _ trigger: Scheme.Trigger = .init(input: .button(.mouse(3)))
    ) throws -> PointerRedirectsToScrollTriggerTransformer {
        try XCTUnwrap(PointerRedirectsToScrollTriggerTransformer(
            trigger: trigger,
            clickDuration: 0.5,
            monotonicClock: { [weak self] in self?.now ?? 0 },
            warpPointer: { [weak self] in self?.warpedPoints.append($0) },
            eventSink: { [weak self] in self?.sentEvents.append($0) },
            redirect: { [weak self] in self?.redirectedEvents.append($0) }
        ))
    }

    private func transform(
        _ transformer: PointerRedirectsToScrollTriggerTransformer,
        _ event: CGEvent
    ) -> CGEvent? {
        transformer.transform(event, in: .init(device: nil))
    }

    private func advance(by seconds: TimeInterval) {
        now += UInt64(seconds * 1_000_000_000)
    }

    private func sentButtonEvents() -> [String] {
        sentEvents.map { event in
            "\(event.type.rawValue):\(event.getIntegerValueField(.mouseEventButtonNumber))"
        }
    }

    private func buttonString(_ type: CGEventType, _ button: Int) -> String {
        "\(type.rawValue):\(button)"
    }

    private func buttonEvent(
        _ type: CGEventType,
        button: Int,
        flags: CGEventFlags = [],
        deltaX: Double = 0,
        deltaY: Double = 0
    ) throws -> CGEvent {
        let mouseButton = try XCTUnwrap(CGMouseButton(rawValue: UInt32(button)))
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: .zero,
            mouseButton: mouseButton
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        event.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
        event.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
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

        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseDragged, button: 3, deltaX: 12, deltaY: -6)))
        XCTAssertNil(try transform(transformer, movedEvent()))
        XCTAssertEqual(redirectedEvents.count, 2)
        XCTAssertEqual(redirectedEvents.first?.getDoubleValueField(.mouseEventDeltaX), 12)
        XCTAssertEqual(redirectedEvents.first?.getDoubleValueField(.mouseEventDeltaY), -6)

        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 3)))
        XCTAssertFalse(transformer.hasActiveInteraction)
        XCTAssertTrue(sentEvents.isEmpty)

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
        // Using the trigger as a hold for another click is not a click itself.
        XCTAssertTrue(sentEvents.isEmpty)
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
        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseDragged, button: 3, deltaX: 20)))
        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 3)))
        XCTAssertEqual(redirectedEvents.count, 1)
    }

    func testPrimaryButtonWithModifierCanBeTheTrigger() throws {
        let transformer = try makeTransformer(.init(input: .button(.mouse(0)), modifiers: [.command]))

        XCTAssertNotNil(try transform(transformer, buttonEvent(.leftMouseDown, button: 0)))
        XCTAssertNotNil(try transform(transformer, buttonEvent(.leftMouseUp, button: 0)))

        XCTAssertNil(try transform(transformer, buttonEvent(.leftMouseDown, button: 0, flags: .maskCommand)))
        XCTAssertNil(try transform(transformer, buttonEvent(.leftMouseDragged, button: 0, deltaY: 20)))
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

    func testQuickClickWithoutMovementIsReplayed() throws {
        let transformer = try makeTransformer()

        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseDown, button: 3)))
        XCTAssertTrue(sentEvents.isEmpty)
        advance(by: 0.2)
        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 3)))

        XCTAssertEqual(sentButtonEvents(), [
            buttonString(.otherMouseDown, 3),
            buttonString(.otherMouseUp, 3)
        ])
        XCTAssertFalse(transformer.hasActiveInteraction)
        XCTAssertTrue(redirectedEvents.isEmpty)
    }

    func testSmallMovementStillClicksAndHoldsTheCursor() throws {
        let transformer = try makeTransformer()

        let down = try buttonEvent(.otherMouseDown, button: 3)
        down.location = CGPoint(x: 100, y: 200)
        XCTAssertNil(transform(transformer, down))
        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseDragged, button: 3, deltaX: 3, deltaY: 4)))
        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseDragged, button: 3, deltaX: 3, deltaY: 4)))
        XCTAssertEqual(warpedPoints, [CGPoint(x: 100, y: 200), CGPoint(x: 100, y: 200)])
        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 3)))

        XCTAssertEqual(sentButtonEvents(), [
            buttonString(.otherMouseDown, 3),
            buttonString(.otherMouseUp, 3)
        ])
        XCTAssertTrue(redirectedEvents.isEmpty)
    }

    func testHoldingWithoutMovementThenReleasingDoesNothing() throws {
        let transformer = try makeTransformer()

        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseDown, button: 3)))
        advance(by: 0.5)
        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 3)))

        XCTAssertTrue(sentEvents.isEmpty)
        XCTAssertTrue(redirectedEvents.isEmpty)
        XCTAssertFalse(transformer.hasActiveInteraction)
    }

    func testMovementPastToleranceScrollsBufferedMovementInOrder() throws {
        let transformer = try makeTransformer()

        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseDown, button: 3)))
        XCTAssertNil(try transform(transformer, movedEvent(deltaX: 0, deltaY: 6)))
        XCTAssertTrue(redirectedEvents.isEmpty)
        XCTAssertNil(try transform(transformer, movedEvent(deltaX: 0, deltaY: 6)))
        XCTAssertEqual(redirectedEvents.map { $0.getDoubleValueField(.mouseEventDeltaY) }, [6, 6])

        // Moving back does not turn the gesture into a click again.
        XCTAssertNil(try transform(transformer, movedEvent(deltaX: 0, deltaY: -12)))
        XCTAssertNil(try transform(transformer, buttonEvent(.otherMouseUp, button: 3)))
        XCTAssertEqual(redirectedEvents.count, 3)
        XCTAssertTrue(sentEvents.isEmpty)
    }

    func testReplayedClickReachesLaterStages() throws {
        final class Recorder: EventTransformer {
            var events = [CGEvent]()

            func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
                events.append(event)
                return event
            }
        }

        let transformer = try makeTransformer()
        let recorder = Recorder()
        let chain: [EventTransformer] = [transformer, recorder]
        var posted = [CGEvent]()
        let context = EventTransformerContext(device: nil) { posted.append($0) }

        XCTAssertNil(try chain.transform(buttonEvent(.otherMouseDown, button: 3), in: context))
        XCTAssertNil(try chain.transform(buttonEvent(.otherMouseUp, button: 3), in: context))

        XCTAssertEqual(recorder.events.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(posted.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertTrue(sentEvents.isEmpty)
    }
}
