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
        event.flags.insert(.maskCommand)
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
        event.flags.insert(.maskCommand)
        event.flags.insert(.maskShift)
        event.flags.insert(.maskAlternate)
        event = try XCTUnwrap(transformer.transform(event, in: EventTransformerContext(device: nil)))
        view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 2)
        XCTAssertEqual(view.deltaY, 4)
    }

    func testZoomAttachesCommandWithoutPressingCommandKey() throws {
        let keySimulator = RecordingModifierKeySimulator()
        let modifiers = Scheme.Scrolling.Modifiers(command: .zoom)
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
        event.flags = .maskCommand

        XCTAssertNil(transformer.transform(event, in: EventTransformerContext(device: nil)))
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
