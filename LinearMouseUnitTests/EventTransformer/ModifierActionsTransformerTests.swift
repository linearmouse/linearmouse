// MIT License
// Copyright (c) 2021-2026 LinearMouse

import KeyKit
@testable import LinearMouse
import XCTest

private final class RecordingModifierKeySimulator: KeySimulating {
    struct ModifiedPress: Equatable {
        let keyCode: CGKeyCode
        let modifierFlags: CGEventFlags
        let restoringModifierFlags: CGEventFlags
    }

    private(set) var unmodifiedPresses: [[Key]] = []
    private(set) var modifiedPresses: [ModifiedPress] = []

    func down(keys _: [Key], tap _: CGEventTapLocation?) throws {}
    func up(keys _: [Key], tap _: CGEventTapLocation?) throws {}

    func press(keys: [Key], tap _: CGEventTapLocation?) throws {
        unmodifiedPresses.append(keys)
    }

    func press(keys _: [Key], modifierFlags _: CGEventFlags, tap _: CGEventTapLocation?) throws {
        XCTFail("Zoom should send a resolved physical shortcut")
    }

    func press(
        keys _: [Key],
        modifierFlags _: CGEventFlags,
        restoringModifierFlags _: CGEventFlags,
        tap _: CGEventTapLocation?
    ) throws {
        XCTFail("Zoom should send a resolved physical shortcut")
    }

    func press(
        keyCode: CGKeyCode,
        modifierFlags: CGEventFlags,
        restoringModifierFlags: CGEventFlags,
        tap _: CGEventTapLocation?
    ) throws {
        modifiedPresses.append(.init(
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            restoringModifierFlags: restoringModifierFlags
        ))
    }

    func reset() {}

    func modifiedCGEventFlags(of _: CGEvent) -> CGEventFlags? {
        nil
    }
}

final class ModifierActionsTransformerTests: XCTestCase {
    /// A layout where zoom-out is not on the US minus key, and zoom-in needs Shift.
    private static func zoomShortcut(zoomIn: Bool) -> KeyEquivalentResolver.Shortcut? {
        .init(keyCode: zoomIn ? 24 : 44, modifierFlags: zoomIn ? [.maskCommand, .maskShift] : .maskCommand)
    }

    func testModifierActions() throws {
        var event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 2,
            wheel3: 0
        ))
        let modifiers = Scheme.Scrolling.Modifiers(
            command: .auto,
            shift: .alterOrientation,
            option: .changeSpeed(scale: 2),
            control: .changeSpeed(scale: 3)
        )
        let transformer = ModifierActionsTransformer(modifiers: .init(vertical: modifiers, horizontal: modifiers))
        event.flags = .maskCommand
        event.flags.insert(.maskShift)
        event.flags.insert(.maskAlternate)
        event.flags.insert(.maskControl)
        event = try XCTUnwrap(transformer.transform(event, in: EventTransformerContext(device: nil)))
        var view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 6)
        XCTAssertEqual(view.deltaY, 12)

        event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 2,
            wheel3: 0
        ))
        event.flags = .maskCommand
        event.flags.insert(.maskShift)
        event.flags.insert(.maskAlternate)
        event = try XCTUnwrap(transformer.transform(event, in: EventTransformerContext(device: nil)))
        view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 2)
        XCTAssertEqual(view.deltaY, 4)
    }

    func testZoomAttachesCommandWithoutPressingCommandKey() throws {
        let keySimulator = RecordingModifierKeySimulator()
        var now: UInt64 = 0
        let modifiers = Scheme.Scrolling.Modifiers(command: .zoom)
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: modifiers, horizontal: modifiers),
            keySimulator: keySimulator,
            monotonicClock: { now },
            zoomShortcut: Self.zoomShortcut
        )
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        event.flags = .maskCommand

        XCTAssertNil(transformer.transform(event, in: EventTransformerContext(device: nil)))
        now = 300_000_000
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -1)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -10)
        XCTAssertNil(transformer.transform(event, in: EventTransformerContext(device: nil)))

        XCTAssertTrue(keySimulator.unmodifiedPresses.isEmpty)
        XCTAssertEqual(
            keySimulator.modifiedPresses,
            [
                .init(
                    keyCode: 24,
                    modifierFlags: [.maskCommand, .maskShift],
                    restoringModifierFlags: .maskCommand
                ),
                .init(
                    keyCode: 44,
                    modifierFlags: .maskCommand,
                    restoringModifierFlags: .maskCommand
                )
            ]
        )
    }

    func testZoomStepsOncePerWheelEventWithoutSharingTheCommandCooldown() throws {
        let simulator = RecordingModifierKeySimulator()
        let throttle = ScrollActionThrottle()
        let recognizer = ScrollActionRecognizer(throttle: throttle)
        let input = ScrollInput(axis: .vertical, delta: 1, units: .detents)
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 0), 1)
        var now: UInt64 = 0
        let modifiers = Scheme.Scrolling.Modifiers(control: .zoom)
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: modifiers, horizontal: modifiers),
            keySimulator: simulator,
            monotonicClock: { now },
            zoomShortcut: Self.zoomShortcut
        )
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0
        ))
        event.flags = .maskControl
        for index in 1 ... 5 {
            now = UInt64(index) * 20_000_000
            XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
            XCTAssertEqual(simulator.modifiedPresses.count, index)
        }
        // Zooming neither checks nor advances the cooldown of mapped commands.
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 300_000_000), 1)
    }

    func testZoomStepsOncePerSideWheelEventRegardlessOfAcceleration() throws {
        let simulator = RecordingModifierKeySimulator()
        let modifiers = Scheme.Scrolling.Modifiers(control: .zoom)
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: modifiers, horizontal: modifiers),
            keySimulator: simulator,
            zoomShortcut: Self.zoomShortcut
        )
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 1, wheel3: 0
        ))
        event.flags = .maskControl
        let view = ScrollWheelEventView(event)
        for fixed in [0.1, 2.07, 8.29] {
            view.deltaXFixedPt = fixed
            XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        }
        XCTAssertEqual(simulator.modifiedPresses.count, 3)
    }

    func testZoomStepsByHighResolutionDetentWhenGivenAMultiplier() throws {
        let simulator = RecordingModifierKeySimulator()
        let modifiers = Scheme.Scrolling.Modifiers(control: .zoom)
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: modifiers, horizontal: modifiers),
            keySimulator: simulator,
            highResolutionWheelMultiplier: { _ in 8 },
            zoomShortcut: Self.zoomShortcut
        )
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0
        ))
        event.flags = .maskControl
        let view = ScrollWheelEventView(event)
        view.deltaYFixedPt = 1.0 / 8
        view.deltaYPt = 1.25
        view.ioHidScrollY = 0
        // Half a detent starts, then every full detent: 4, 12, 20 of 24 pieces.
        for _ in 0 ..< 24 {
            XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        }
        XCTAssertEqual(simulator.modifiedPresses.count, 3)
    }

    func testZoomStepsEvery32PointsOfContinuousInput() throws {
        let simulator = RecordingModifierKeySimulator()
        let modifiers = Scheme.Scrolling.Modifiers(control: .zoom)
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: modifiers, horizontal: modifiers),
            keySimulator: simulator,
            zoomShortcut: Self.zoomShortcut
        )
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 4, wheel2: 0, wheel3: 0
        ))
        event.flags = .maskControl
        let view = ScrollWheelEventView(event)
        view.deltaYPt = 4
        view.scrollPhase = .began
        XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        view.scrollPhase = .changed
        for _ in 1 ..< 36 {
            XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        }
        // 144 points: 16, 48, 80, 112, 144.
        XCTAssertEqual(simulator.modifiedPresses.count, 5)
    }

    func testZoomMomentumStaysConsumedAfterModifierReleaseAndOnAnotherRoute() throws {
        let simulator = RecordingModifierKeySimulator()
        let ownership = ScrollGestureOwnership()
        let modifiers = Scheme.Scrolling.Modifiers(control: .zoom)
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: modifiers, horizontal: modifiers),
            keySimulator: simulator,
            scrollGesture: ownership,
            zoomShortcut: Self.zoomShortcut
        )
        let pipeline: [EventTransformer] = [ScrollGestureTransformer(ownership: ownership), transformer]
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 16, wheel2: 0, wheel3: 0
        ))
        event.flags = .maskControl
        XCTAssertNil(pipeline.transform(event, in: .init(device: nil)))
        XCTAssertEqual(simulator.modifiedPresses.count, 1)
        event.flags = []
        let view = ScrollWheelEventView(event)
        view.momentumPhase = .begin
        XCTAssertNil(pipeline.transform(event, in: .init(device: nil)))
        let next = ScrollGestureTransformer(ownership: ownership)
        XCTAssertNil(next.transform(event, in: .init(device: nil)))
        view.momentumPhase = .end
        XCTAssertNil(next.transform(event, in: .init(device: nil)))
        view.momentumPhase = .none
        view.scrollPhase = .began
        XCTAssertNotNil(pipeline.transform(event, in: .init(device: nil)))
        XCTAssertEqual(simulator.modifiedPresses.count, 1)
    }

    func testDirectScrollingAfterReleasingZoomModifierRestoresNativeMomentum() throws {
        let simulator = RecordingModifierKeySimulator()
        let ownership = ScrollGestureOwnership()
        let modifiers = Scheme.Scrolling.Modifiers(control: .zoom)
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: modifiers, horizontal: modifiers),
            keySimulator: simulator,
            scrollGesture: ownership,
            zoomShortcut: Self.zoomShortcut
        )
        let pipeline: [EventTransformer] = [ScrollGestureTransformer(ownership: ownership), transformer]
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 16, wheel2: 0, wheel3: 0
        ))
        let view = ScrollWheelEventView(event)
        view.momentumPhase = .none
        view.scrollPhase = .changed
        event.flags = .maskControl
        XCTAssertNil(pipeline.transform(event, in: .init(device: nil)))
        XCTAssertTrue(ownership.isOwned)
        event.flags = []
        XCTAssertNotNil(pipeline.transform(event, in: .init(device: nil)))
        XCTAssertFalse(ownership.isOwned)
        view.scrollPhase = nil
        view.momentumPhase = .begin
        XCTAssertNotNil(pipeline.transform(event, in: .init(device: nil)))
        XCTAssertEqual(simulator.modifiedPresses.count, 1)
    }

    func testZoomDiscardsProgressAtMovementFreeGestureBoundaries() throws {
        let simulator = RecordingModifierKeySimulator()
        let modifiers = Scheme.Scrolling.Modifiers(control: .zoom)
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: modifiers, horizontal: modifiers),
            keySimulator: simulator,
            zoomShortcut: Self.zoomShortcut
        )
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 12, wheel2: 0, wheel3: 0
        ))
        event.flags = .maskControl
        let view = ScrollWheelEventView(event)
        view.deltaYPt = 12
        view.scrollPhase = .began
        XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        let boundary = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0
        ))
        boundary.flags = .maskControl
        for phase: CGScrollPhase in [.ended, .began] {
            ScrollWheelEventView(boundary).scrollPhase = phase
            XCTAssertNotNil(transformer.transform(boundary, in: .init(device: nil)))
        }
        view.deltaYPt = 4
        view.scrollPhase = .changed
        XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        XCTAssertTrue(simulator.modifiedPresses.isEmpty)
    }

    func testZoomDiscardsProgressAtBoundariesWhileTheModifierIsReleased() throws {
        let simulator = RecordingModifierKeySimulator()
        let modifiers = Scheme.Scrolling.Modifiers(control: .zoom)
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: modifiers, horizontal: modifiers),
            keySimulator: simulator,
            zoomShortcut: Self.zoomShortcut
        )
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 12, wheel2: 0, wheel3: 0
        ))
        let view = ScrollWheelEventView(event)
        view.deltaYPt = 12
        event.flags = .maskControl
        view.scrollPhase = .began
        XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        event.flags = []
        for phase: CGScrollPhase in [.ended, .began] {
            view.scrollPhase = phase
            XCTAssertNotNil(transformer.transform(event, in: .init(device: nil)))
        }
        event.flags = .maskControl
        view.deltaYPt = 4
        view.scrollPhase = .changed
        XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        XCTAssertTrue(simulator.modifiedPresses.isEmpty)
    }

    func testZoomIgnoresMomentum() throws {
        let simulator = RecordingModifierKeySimulator()
        let modifiers = Scheme.Scrolling.Modifiers(control: .zoom)
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: modifiers, horizontal: modifiers),
            keySimulator: simulator,
            zoomShortcut: Self.zoomShortcut
        )
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0
        ))
        event.flags = .maskControl
        XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        ScrollWheelEventView(event).momentumPhase = .begin
        XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        XCTAssertEqual(simulator.modifiedPresses.count, 1)
    }

    func testZoomRestoresNonCommandTriggerModifier() throws {
        let keySimulator = RecordingModifierKeySimulator()
        let modifiers = Scheme.Scrolling.Modifiers(option: .zoom)
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: modifiers, horizontal: modifiers),
            keySimulator: keySimulator,
            zoomShortcut: Self.zoomShortcut
        )
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        let leftOptionFlag = CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))
        event.flags = [.maskAlternate, leftOptionFlag]

        XCTAssertNil(transformer.transform(event, in: EventTransformerContext(device: nil)))
        XCTAssertEqual(
            keySimulator.modifiedPresses,
            [
                .init(
                    keyCode: 24,
                    modifierFlags: [.maskCommand, .maskShift],
                    restoringModifierFlags: [.maskAlternate, leftOptionFlag]
                )
            ]
        )
    }

    func testHorizontalReversedZoomUsesTheOppositeResolvedShortcut() throws {
        let simulator = RecordingModifierKeySimulator()
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: nil, horizontal: .init(control: .zoomReversed)),
            keySimulator: simulator,
            zoomShortcut: Self.zoomShortcut
        )
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 1,
            wheel3: 0
        ))
        event.flags = .maskControl

        XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        XCTAssertEqual(simulator.modifiedPresses, [
            .init(keyCode: 44, modifierFlags: .maskCommand, restoringModifierFlags: .maskControl)
        ])
    }

    func testZoomDoesNotSendAnOldOrGuessedShortcutWhileLayoutIsUnresolved() throws {
        let simulator = RecordingModifierKeySimulator()
        let transformer = ModifierActionsTransformer(
            modifiers: .init(vertical: .init(command: .zoom), horizontal: nil),
            keySimulator: simulator
        ) { _ in nil }
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        event.flags = .maskCommand

        XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        XCTAssertTrue(simulator.modifiedPresses.isEmpty)
        XCTAssertTrue(simulator.unmodifiedPresses.isEmpty)
    }
}
