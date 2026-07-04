// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class PointerLocationDoubleModifierTriggerTests: XCTestCase {
    func testDoubleControlTapTriggersPointerLocation() {
        var trigger = PointerLocationDoubleModifierTrigger()

        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskControl], at: 1.00))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 1.08))
        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskControl], at: 1.32))
        XCTAssertTrue(flagsChanged(&trigger, flags: [], at: 1.40))
    }

    func testSingleControlTapDoesNotTriggerPointerLocation() {
        var trigger = PointerLocationDoubleModifierTrigger()

        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskControl], at: 1.00))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 1.08))
    }

    func testDelayedSecondTapDoesNotTriggerPointerLocation() {
        var trigger = PointerLocationDoubleModifierTrigger()

        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskControl], at: 1.00))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 1.08))
        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskControl], at: 4.00))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 4.08))
    }

    func testLongSecondPressDoesNotTriggerPointerLocation() {
        var trigger = PointerLocationDoubleModifierTrigger()

        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskControl], at: 1.00))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 1.08))
        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskControl], at: 1.30))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 1.80))
    }

    func testControlShortcutCancelsPendingTap() {
        var trigger = PointerLocationDoubleModifierTrigger()

        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskControl], at: 1.00))
        XCTAssertFalse(trigger.handle(
            eventType: .keyDown,
            flags: [.maskControl],
            timestamp: 1.10,
            triggerModifier: .control
        ))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 1.18))
        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskControl], at: 1.30))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 1.38))
    }

    func testOtherKeyBetweenTapsCancelsPendingSequence() {
        var trigger = PointerLocationDoubleModifierTrigger()

        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskControl], at: 1.00))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 1.08))
        XCTAssertFalse(trigger.handle(
            eventType: .keyDown,
            flags: [],
            timestamp: 1.20,
            triggerModifier: .control
        ))
        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskControl], at: 1.30))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 1.38))
    }

    func testDifferentModifierDoesNotTriggerControlConfiguration() {
        var trigger = PointerLocationDoubleModifierTrigger()

        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskAlternate], at: 1.00))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 1.08))
        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskAlternate], at: 1.30))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 1.38))
    }

    func testOptionConfigurationTriggersOnDoubleOptionTap() {
        var trigger = PointerLocationDoubleModifierTrigger()

        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskAlternate], at: 1.00, triggerModifier: .option))
        XCTAssertFalse(flagsChanged(&trigger, flags: [], at: 1.08, triggerModifier: .option))
        XCTAssertFalse(flagsChanged(&trigger, flags: [.maskAlternate], at: 1.30, triggerModifier: .option))
        XCTAssertTrue(flagsChanged(&trigger, flags: [], at: 1.38, triggerModifier: .option))
    }

    private func flagsChanged(
        _ trigger: inout PointerLocationDoubleModifierTrigger,
        flags: CGEventFlags,
        at timestamp: TimeInterval,
        triggerModifier: PointerLocationTriggerModifier = .control
    ) -> Bool {
        trigger.handle(
            eventType: .flagsChanged,
            flags: flags,
            timestamp: timestamp,
            triggerModifier: triggerModifier
        )
    }
}
