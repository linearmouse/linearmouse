// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Carbon
@testable import KeyKit
import XCTest

final class KeySimulatorEventFieldsTests: XCTestCase {
    /// Simulated key events must be indistinguishable from hardware ones:
    /// events without HID system state, with a zero timestamp or without a
    /// keyboard type break mouse capture in some event consumers (e.g. Wine
    /// games holding a mouse button to rotate the camera).
    func testSimulatedKeyEventsMimicHardwareEvents() throws {
        var recordedEvents: [CGEvent] = []
        let simulator = KeySimulator { event, _ in
            recordedEvents.append(event)
        }

        let before = DispatchTime.now().uptimeNanoseconds
        try simulator.press(keys: [.f1], tap: nil)
        let after = DispatchTime.now().uptimeNanoseconds
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))

        XCTAssertEqual(recordedEvents.map(\.type), [.keyDown, .keyUp])
        for event in recordedEvents {
            XCTAssertEqual(
                event.getIntegerValueField(.eventSourceStateID),
                Int64(CGEventSourceStateID.hidSystemState.rawValue)
            )
            XCTAssertGreaterThanOrEqual(event.timestamp, before)
            XCTAssertLessThanOrEqual(event.timestamp, after)
            XCTAssertEqual(
                event.getIntegerValueField(.keyboardEventKeyboardType),
                Int64(source.keyboardType)
            )
        }
    }

    func testResolvedShortcutKeepsPhysicalKeyCodeAndRestoresCommandAfterShift() throws {
        var events: [CGEvent] = []
        var taps: [CGEventTapLocation?] = []
        let simulator = KeySimulator(eventSourceUserData: 1234) { event, tap in
            events.append(event)
            taps.append(tap)
        }
        let rightCommand = CGEventFlags(rawValue: UInt64(NX_DEVICERCMDKEYMASK))

        try simulator.press(
            keyCode: 44,
            modifierFlags: [.maskCommand, .maskShift],
            restoringModifierFlags: [.maskCommand, rightCommand],
            tap: .cgSessionEventTap
        )

        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp, .flagsChanged])
        XCTAssertEqual(events.prefix(2).map { $0.getIntegerValueField(.keyboardEventKeycode) }, [44, 44])
        XCTAssertTrue(events.prefix(2).allSatisfy {
            $0.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == [
                .maskCommand,
                .maskShift
            ]
        })
        let restored = try XCTUnwrap(events.last)
        XCTAssertEqual(restored.getIntegerValueField(.keyboardEventKeycode), Int64(kVK_Shift))
        XCTAssertTrue(restored.flags.contains([.maskCommand, rightCommand]))
        XCTAssertFalse(restored.flags.contains(.maskShift))
        XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == 1234 })
        XCTAssertTrue(taps.allSatisfy { $0 == .cgSessionEventTap })
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
        XCTAssertTrue(events.allSatisfy {
            $0.timestamp > 0 &&
                $0.getIntegerValueField(.keyboardEventKeyboardType) == Int64(source.keyboardType)
        })
    }

    func testResolvedShortcutRestoresOptionWithoutKeepingCommandOrShift() throws {
        var events: [CGEvent] = []
        let simulator = KeySimulator { event, _ in events.append(event) }
        let rightOption = CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK))
        try simulator.press(
            keyCode: 24,
            modifierFlags: [.maskCommand, .maskShift],
            restoringModifierFlags: [.maskAlternate, rightOption],
            tap: nil
        )
        let restored = try XCTUnwrap(events.last)
        XCTAssertEqual(restored.type, .flagsChanged)
        XCTAssertEqual(restored.getIntegerValueField(.keyboardEventKeycode), Int64(kVK_RightOption))
        XCTAssertTrue(restored.flags.contains([.maskAlternate, rightOption]))
        XCTAssertTrue(restored.flags.isDisjoint(with: [.maskCommand, .maskShift]))
    }
}
