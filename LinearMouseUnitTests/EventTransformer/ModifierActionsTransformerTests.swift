// MIT License
// Copyright (c) 2021-2026 LinearMouse

import KeyKit
@testable import LinearMouse
import XCTest

private final class RecordingModifierKeySimulator: KeySimulating {
    struct ModifiedPress: Equatable {
        let keys: [Key]
        let modifierFlags: CGEventFlags
        let restoringModifierFlags: CGEventFlags?
    }

    private(set) var unmodifiedPresses: [[Key]] = []
    private(set) var modifiedPresses: [ModifiedPress] = []

    func down(keys _: [Key], tap _: CGEventTapLocation?) throws {}
    func up(keys _: [Key], tap _: CGEventTapLocation?) throws {}

    func press(keys: [Key], tap _: CGEventTapLocation?) throws {
        unmodifiedPresses.append(keys)
    }

    func press(
        keys: [Key],
        modifierFlags: CGEventFlags,
        tap _: CGEventTapLocation?
    ) throws {
        modifiedPresses.append(.init(
            keys: keys,
            modifierFlags: modifierFlags,
            restoringModifierFlags: nil
        ))
    }

    func press(
        keys: [Key],
        modifierFlags: CGEventFlags,
        restoringModifierFlags: CGEventFlags,
        tap _: CGEventTapLocation?
    ) throws {
        modifiedPresses.append(.init(
            keys: keys,
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
            keySimulator: keySimulator
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
                    keys: [.numpadPlus],
                    modifierFlags: .maskCommand,
                    restoringModifierFlags: .maskCommand
                ),
                .init(
                    keys: [.numpadMinus],
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
            keySimulator: keySimulator
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
                    keys: [.numpadPlus],
                    modifierFlags: .maskCommand,
                    restoringModifierFlags: [.maskAlternate, leftOptionFlag]
                )
            ]
        )
    }
}
