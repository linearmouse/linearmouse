// MIT License
// Copyright (c) 2021-2026 LinearMouse

import KeyKit
@testable import LinearMouse
import XCTest

final class ButtonMappingEngineTests: XCTestCase {
    private typealias Mapping = Scheme.Buttons.Mapping
    private typealias Button = Mapping.Button
    private typealias Action = Mapping.Action

    private let shortAction: Action = .arg0(.missionControl)
    private let longAction: Action = .arg0(.launchpad)
    private let chordAction: Action = .arg0(.showDesktop)
    private let wheelAction: Action = .arg0(.appExpose)

    func testShortPressExecutesOnlyOnRelease() {
        var engine = engine([buttonMapping(4, short: shortAction)])

        XCTAssertEqual(engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0)).actions, [])
        XCTAssertEqual(engine.state, .tracking)
        XCTAssertEqual(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(100)).actions, [shortAction])
        XCTAssertEqual(engine.state, .idle)
    }

    func testLongPressExecutesAtGlobalDeadlineAndSuppressesShortPress() {
        var engine = engine([buttonMapping(4, short: shortAction, long: longAction)])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        XCTAssertEqual(engine.advance(to: ms(499)).actions, [])
        XCTAssertEqual(engine.advance(to: ms(500)).actions, [longAction])
        XCTAssertEqual(engine.state, .committed)
        XCTAssertEqual(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(600)).actions, [])
    }

    func testSeparateEntriesForSameTriggerMergeAtRuntime() {
        var engine = engine([
            buttonMapping(4, short: shortAction),
            buttonMapping(4, long: longAction)
        ])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        XCTAssertEqual(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(100)).actions, [shortAction])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(200))
        XCTAssertEqual(engine.advance(to: ms(700)).actions, [longAction])
    }

    func testLaterDuplicateOutcomeOverridesEarlierEntry() {
        var engine = engine([
            buttonMapping(4, short: shortAction),
            buttonMapping(4, short: chordAction)
        ])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        XCTAssertEqual(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(100)).actions, [chordAction])
    }

    func testSwipeExecutesBeforeReleaseAndSuppressesShortAndLongPress() {
        let mapping = buttonMapping(
            4,
            short: shortAction,
            long: longAction,
            swipe: .init(right: chordAction)
        )
        var engine = engine([mapping])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        XCTAssertEqual(engine.pointerMoved(deltaX: 20, deltaY: 0, at: ms(50)).actions, [])
        XCTAssertEqual(engine.pointerMoved(deltaX: 31, deltaY: 0, at: ms(100)).actions, [chordAction])
        XCTAssertEqual(engine.advance(to: ms(600)).actions, [])
        XCTAssertEqual(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(700)).actions, [])
    }

    func testLongPressWinsWhenItsDeadlinePrecedesSwipe() {
        var engine = engine([
            buttonMapping(4, short: shortAction, long: longAction, swipe: .init(right: chordAction))
        ])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        XCTAssertEqual(engine.advance(to: ms(500)).actions, [longAction])
        XCTAssertEqual(engine.pointerMoved(deltaX: 60, deltaY: 0, at: ms(510)).actions, [])
    }

    func testChordBeatsItsSingleButtonPrefix() {
        let single = buttonMapping(4, short: shortAction)
        let chord = buttonMapping(4, simultaneous: [5], short: chordAction)
        var engine = engine([single, chord])

        XCTAssertTrue(engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0)).consumesEvent)
        XCTAssertEqual(engine.state, .waitingForChord)
        XCTAssertTrue(engine.buttonDown(.mouse(5), modifierFlags: [], at: ms(40)).consumesEvent)
        XCTAssertEqual(engine.state, .tracking)
        XCTAssertEqual(engine.buttonUp(.mouse(5), modifierFlags: [], at: ms(70)).actions, [chordAction])
        XCTAssertEqual(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(80)).actions, [])
    }

    func testChordInteractionRemainsActiveUntilEveryButtonIsReleased() {
        var engine = engine([buttonMapping(0, simultaneous: [1], short: .arg0(.none))])

        _ = engine.buttonDown(.mouse(0), modifierFlags: [], at: ms(0))
        _ = engine.buttonDown(.mouse(1), modifierFlags: [], at: ms(40))
        XCTAssertTrue(engine.hasActiveInteraction)

        _ = engine.buttonUp(.mouse(0), modifierFlags: [], at: ms(60))
        XCTAssertTrue(engine.hasActiveInteraction)

        _ = engine.buttonUp(.mouse(1), modifierFlags: [], at: ms(80))
        XCTAssertFalse(engine.hasActiveInteraction)
    }

    func testSingleButtonFallbackResolvesAfterChordWindow() {
        var engine = engine([
            buttonMapping(4, short: shortAction),
            buttonMapping(4, simultaneous: [5], short: chordAction)
        ])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        XCTAssertEqual(engine.advance(to: ms(79)).actions, [])
        XCTAssertEqual(engine.state, .waitingForChord)
        XCTAssertEqual(engine.advance(to: ms(80)).actions, [])
        XCTAssertEqual(engine.state, .tracking)
        XCTAssertEqual(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(90)).actions, [shortAction])
    }

    func testSwipeAccumulatedWhileWaitingForChordFiresWhenSingleButtonResolves() {
        var engine = engine([
            buttonMapping(4, swipe: .init(right: chordAction)),
            buttonMapping(4, simultaneous: [5], short: shortAction)
        ])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        XCTAssertEqual(engine.pointerMoved(deltaX: 60, deltaY: 0, at: ms(40)).actions, [])
        XCTAssertEqual(engine.advance(to: ms(80)).actions, [chordAction])
        XCTAssertEqual(engine.state, .committed)
    }

    func testChordOutsideWindowPassesLateButtonAndForwardsCapturedRelease() {
        var engine = engine([buttonMapping(4, simultaneous: [5], short: chordAction)])

        XCTAssertFalse(engine.hasActiveInteraction)
        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        XCTAssertTrue(engine.hasActiveInteraction)
        XCTAssertTrue(engine.advance(to: ms(80)).replaysBufferedEvents)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertTrue(engine.hasActiveInteraction)
        XCTAssertFalse(engine.buttonDown(.mouse(5), modifierFlags: [], at: ms(100)).consumesEvent)
        XCTAssertFalse(engine.buttonUp(.mouse(5), modifierFlags: [], at: ms(110)).consumesEvent)

        let release = engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(120))
        XCTAssertTrue(release.consumesEvent)
        XCTAssertTrue(release.forwardsCapturedEvent)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertFalse(engine.hasActiveInteraction)
    }

    func testFailedChordForwardsDragUntilCapturedButtonIsReleased() {
        var engine = engine([buttonMapping(4, simultaneous: [5], short: chordAction)])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        XCTAssertTrue(engine.advance(to: ms(80)).replaysBufferedEvents)

        let movement = engine.pointerMoved(for: .mouse(4), deltaX: 4, deltaY: 2, at: ms(90))
        XCTAssertTrue(movement.consumesEvent)
        XCTAssertTrue(movement.forwardsCapturedEvent)

        let release = engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(100))
        XCTAssertTrue(release.consumesEvent)
        XCTAssertTrue(release.forwardsCapturedEvent)
        XCTAssertFalse(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(110)).consumesEvent)
    }

    func testLongestCompletedChordWins() {
        var engine = engine([
            buttonMapping(4, simultaneous: [5], short: shortAction),
            buttonMapping(4, simultaneous: [5, 6], short: chordAction)
        ])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        _ = engine.buttonDown(.mouse(5), modifierFlags: [], at: ms(20))
        XCTAssertEqual(engine.state, .waitingForChord)
        _ = engine.buttonDown(.mouse(6), modifierFlags: [], at: ms(40))
        XCTAssertEqual(engine.buttonUp(.mouse(6), modifierFlags: [], at: ms(50)).actions, [chordAction])
    }

    func testMissingShortPressReplaysBufferedButtonEvents() {
        var engine = engine([buttonMapping(4, long: longAction)])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        let output = engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(100))

        XCTAssertTrue(output.consumesEvent)
        XCTAssertTrue(output.replaysBufferedEvents)
        XCTAssertEqual(output.actions, [])
    }

    func testAutoOnlyMappingPassesThroughWithoutCapturingButtonEvents() {
        var legacyMapping = Mapping()
        legacyMapping.button = .mouse(4)
        legacyMapping.action = .arg0(.auto)
        var engine = engine([legacyMapping])

        XCTAssertFalse(engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0)).consumesEvent)
        XCTAssertFalse(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(100)).consumesEvent)
        XCTAssertEqual(engine.state, .idle)
    }

    func testModifierMatchIsExact() {
        let mapping = buttonMapping(4, modifiers: [.command], short: shortAction)
        var engine = engine([mapping])

        XCTAssertFalse(engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0)).consumesEvent)
        XCTAssertFalse(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(10)).consumesEvent)
        XCTAssertTrue(engine.buttonDown(.mouse(4), modifierFlags: [.maskCommand], at: ms(20)).consumesEvent)
        XCTAssertEqual(
            engine.buttonUp(.mouse(4), modifierFlags: [.maskCommand], at: ms(30)).actions,
            [shortAction]
        )
    }

    func testVerticalAndHorizontalWheelDirectionsAreIndependent() {
        var engine = engine([
            wheelMapping(.up, action: wheelAction),
            wheelMapping(.left, action: chordAction)
        ])

        XCTAssertEqual(engine.wheel(.up, modifierFlags: [], at: ms(0)).actions, [wheelAction])
        XCTAssertEqual(engine.wheel(.left, modifierFlags: [], at: ms(1)).actions, [chordAction])
        XCTAssertFalse(engine.wheel(.right, modifierFlags: [], at: ms(2)).consumesEvent)
    }

    func testHeldButtonWheelMappingBeatsPlainWheelMapping() {
        var engine = engine([
            wheelMapping(.up, action: shortAction),
            wheelMapping(.up, whileHeld: [4], action: wheelAction)
        ])

        XCTAssertEqual(engine.wheel(.up, modifierFlags: [], at: ms(0)).actions, [shortAction])
        XCTAssertTrue(engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(10)).consumesEvent)
        XCTAssertEqual(engine.wheel(.up, modifierFlags: [], at: ms(20)).actions, [wheelAction])
        XCTAssertEqual(engine.wheel(.up, modifierFlags: [], at: ms(30)).actions, [wheelAction])
        XCTAssertEqual(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(40)).actions, [])
    }

    func testWheelUseCancelsPendingShortPressOnHeldButton() {
        var engine = engine([
            buttonMapping(4, short: shortAction),
            wheelMapping(.down, whileHeld: [4], action: wheelAction)
        ])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        XCTAssertEqual(engine.wheel(.down, modifierFlags: [], at: ms(50)).actions, [wheelAction])
        XCTAssertEqual(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(100)).actions, [])
    }

    func testWheelCapturesEveryButtonInAMultiButtonHeldPrefix() {
        var engine = engine([
            wheelMapping(.down, whileHeld: [4, 5], action: wheelAction)
        ])

        XCTAssertTrue(engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0)).consumesEvent)
        XCTAssertTrue(engine.buttonDown(.mouse(5), modifierFlags: [], at: ms(100)).consumesEvent)
        XCTAssertEqual(engine.wheel(.down, modifierFlags: [], at: ms(200)).actions, [wheelAction])
        XCTAssertTrue(engine.buttonUp(.mouse(5), modifierFlags: [], at: ms(210)).consumesEvent)
        XCTAssertTrue(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(220)).consumesEvent)
    }

    func testLongPressMakesButtonUnavailableToHeldWheelMapping() {
        var engine = engine([
            buttonMapping(4, long: longAction),
            wheelMapping(.up, whileHeld: [4], action: wheelAction)
        ])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        XCTAssertEqual(engine.advance(to: ms(500)).actions, [longAction])
        XCTAssertFalse(engine.wheel(.up, modifierFlags: [], at: ms(510)).consumesEvent)
    }

    func testResetReplaysOnlyUncommittedSession() {
        var pending = engine([buttonMapping(4, short: shortAction)])
        _ = pending.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        XCTAssertTrue(pending.reset().replaysBufferedEvents)

        var committed = engine([buttonMapping(4, long: longAction)])
        _ = committed.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        _ = committed.advance(to: ms(500))
        XCTAssertFalse(committed.reset().replaysBufferedEvents)
    }

    func testPressOutcomeBeginsOnResolutionAndEndsOnRelease() {
        let press = Mapping.PressAction(action: .arg1(.keyPress([.a])), behavior: .hold)
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: press)
        )
        var engine = engine([mapping])

        let down = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        let up = engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(100))

        XCTAssertEqual(down.lifecycleEvents, [.began(press, buttons: [.mouse(4)])])
        XCTAssertEqual(up.lifecycleEvents, [.ended(press, buttons: [.mouse(4)])])
        XCTAssertEqual(engine.state, .idle)
    }

    func testDuplicatePressedReportDoesNotBeginPressLifecycleAgain() {
        let press = Mapping.PressAction(action: .arg1(.keyPress([.a])), behavior: .hold)
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: press)
        )
        var engine = engine([mapping])

        XCTAssertEqual(
            engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0)).lifecycleEvents,
            [.began(press, buttons: [.mouse(4)])]
        )
        let duplicate = engine.buttonDown(.mouse(4), modifierFlags: [.maskCommand], at: ms(10))
        XCTAssertTrue(duplicate.consumesEvent)
        XCTAssertTrue(duplicate.lifecycleEvents.isEmpty)
        XCTAssertEqual(
            engine.buttonUp(.mouse(4), modifierFlags: [.maskCommand], at: ms(20)).lifecycleEvents,
            [.ended(press, buttons: [.mouse(4)])]
        )
    }

    func testIndependentPressOutcomesCanOverlap() {
        let firstPress = Mapping.PressAction(action: .arg1(.keyPress([.command])), behavior: .hold)
        let secondPress = Mapping.PressAction(action: .arg1(.keyPress([.shift])), behavior: .hold)
        var engine = engine([
            Mapping(
                trigger: .init(input: .button(.mouse(4))),
                outcomes: .init(press: firstPress)
            ),
            Mapping(
                trigger: .init(input: .button(.mouse(5))),
                outcomes: .init(press: secondPress)
            )
        ])

        XCTAssertEqual(
            engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0)).lifecycleEvents,
            [.began(firstPress, buttons: [.mouse(4)])]
        )
        XCTAssertEqual(
            engine.buttonDown(.mouse(5), modifierFlags: [], at: ms(10)).lifecycleEvents,
            [.began(secondPress, buttons: [.mouse(5)])]
        )
        XCTAssertEqual(
            engine.buttonUp(.mouse(5), modifierFlags: [], at: ms(20)).lifecycleEvents,
            [.ended(secondPress, buttons: [.mouse(5)])]
        )
        XCTAssertEqual(
            engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(30)).lifecycleEvents,
            [.ended(firstPress, buttons: [.mouse(4)])]
        )
    }

    func testRepeatPressForwardsDraggedMovementAsPointerMovement() {
        let press = Mapping.PressAction(action: .arg0(.missionControl), behavior: .repeat)
        var engine = engine([
            Mapping(
                trigger: .init(input: .button(.mouse(4))),
                outcomes: .init(press: press)
            )
        ])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        let movement = engine.pointerMoved(for: .mouse(4), deltaX: 4, deltaY: 2, at: ms(10))

        XCTAssertTrue(movement.consumesEvent)
        XCTAssertEqual(movement.pointerHandling, .forwardAsMovement)
    }

    func testPendingSideButtonDoesNotCaptureUnrelatedPrimaryDrag() {
        var engine = engine([buttonMapping(4, long: longAction)])

        XCTAssertTrue(engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0)).consumesEvent)

        let movement = engine.pointerMoved(
            for: .mouse(0),
            deltaX: 4,
            deltaY: 2,
            at: ms(10)
        )

        XCTAssertFalse(movement.consumesEvent)
        XCTAssertFalse(movement.buffersEvent)
        XCTAssertEqual(engine.state, .tracking)
    }

    func testOrderedHeldButtonThenTriggerButton() {
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(5)), whileHeld: [.mouse(4)]),
            outcomes: .init(shortPress: chordAction)
        )
        var engine = engine([mapping])

        XCTAssertTrue(engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0)).consumesEvent)
        XCTAssertTrue(engine.buttonDown(.mouse(5), modifierFlags: [], at: ms(200)).consumesEvent)
        XCTAssertEqual(engine.buttonUp(.mouse(5), modifierFlags: [], at: ms(250)).actions, [chordAction])
        XCTAssertEqual(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(260)).actions, [])
    }

    func testOrderedPrimaryInputDoesNotCaptureOrdinaryPrimaryStream() {
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(0)), whileHeld: [.mouse(4)]),
            outcomes: .init(shortPress: chordAction)
        )
        var engine = engine([mapping])

        XCTAssertFalse(engine.buttonDown(.mouse(0), modifierFlags: [], at: ms(0)).consumesEvent)
        XCTAssertFalse(engine.hasActiveInteraction)
        XCTAssertFalse(
            engine.pointerMoved(for: .mouse(0), deltaX: 10, deltaY: 0, at: ms(10)).consumesEvent
        )
        XCTAssertFalse(engine.buttonUp(.mouse(0), modifierFlags: [], at: ms(20)).consumesEvent)
    }

    func testPrimaryHeldPrefixCapturesPrimaryStreamUntilRelease() {
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4)), whileHeld: [.mouse(0)]),
            outcomes: .init(shortPress: chordAction)
        )
        var engine = engine([mapping])

        XCTAssertTrue(engine.buttonDown(.mouse(0), modifierFlags: [], at: ms(0)).consumesEvent)
        XCTAssertTrue(engine.hasActiveInteraction)
        XCTAssertTrue(
            engine.pointerMoved(for: .mouse(0), deltaX: 10, deltaY: 0, at: ms(10)).consumesEvent
        )
        let release = engine.buttonUp(.mouse(0), modifierFlags: [], at: ms(20))
        XCTAssertTrue(release.consumesEvent)
        XCTAssertTrue(release.replaysBufferedEvents)
        XCTAssertFalse(engine.hasActiveInteraction)
    }

    func testOrderedTriggerTakesPriorityOverHeldButtonsOwnShortPress() {
        let ordered = Mapping(
            trigger: .init(input: .button(.mouse(5)), whileHeld: [.mouse(4)]),
            outcomes: .init(shortPress: chordAction)
        )
        var engine = engine([buttonMapping(4, short: shortAction), ordered])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        _ = engine.buttonDown(.mouse(5), modifierFlags: [], at: ms(200))
        XCTAssertEqual(engine.buttonUp(.mouse(5), modifierFlags: [], at: ms(250)).actions, [chordAction])
        XCTAssertEqual(engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(260)).actions, [])
    }

    func testUnusedHeldPrefixReplaysItsClick() {
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(5)), whileHeld: [.mouse(4)]),
            outcomes: .init(shortPress: chordAction)
        )
        var engine = engine([mapping])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        let release = engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(100))

        XCTAssertTrue(release.replaysBufferedEvents)
        XCTAssertEqual(release.actions, [])
    }

    func testReleasingHeldPrefixCommitsOrderedShortPress() {
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(5)), whileHeld: [.mouse(4)]),
            outcomes: .init(shortPress: chordAction)
        )
        var engine = engine([mapping])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        _ = engine.buttonDown(.mouse(5), modifierFlags: [], at: ms(100))
        let prefixRelease = engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(150))
        let triggerRelease = engine.buttonUp(.mouse(5), modifierFlags: [], at: ms(200))

        XCTAssertFalse(prefixRelease.replaysBufferedEvents)
        XCTAssertEqual(prefixRelease.actions, [chordAction])
        XCTAssertEqual(triggerRelease.actions, [])
    }

    func testReleasingHeldPrefixReplaysWhenOrderedShortPressIsUndefined() {
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(5)), whileHeld: [.mouse(4)]),
            outcomes: .init(longPress: longAction)
        )
        var engine = engine([mapping])

        _ = engine.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        _ = engine.buttonDown(.mouse(5), modifierFlags: [], at: ms(100))
        let release = engine.buttonUp(.mouse(4), modifierFlags: [], at: ms(150))

        XCTAssertTrue(release.replaysBufferedEvents)
        XCTAssertEqual(release.actions, [])
        let triggerRelease = engine.buttonUp(.mouse(5), modifierFlags: [], at: ms(200))
        XCTAssertTrue(triggerRelease.consumesEvent)
        XCTAssertTrue(triggerRelease.forwardsCapturedEvent)
    }

    private func engine(_ mappings: [Mapping]) -> ButtonMappingEngine {
        .init(mappings: mappings, policy: .default)
    }

    private func buttonMapping(
        _ button: Int,
        simultaneous: [Int] = [],
        modifiers: [Mapping.Modifier] = [],
        short: Action? = nil,
        long: Action? = nil,
        swipe: Mapping.SwipeActions? = nil
    ) -> Mapping {
        .init(
            trigger: .init(
                input: .button(.mouse(button)),
                simultaneous: simultaneous.map(Button.mouse),
                modifiers: modifiers
            ),
            outcomes: .init(shortPress: short, longPress: long, swipe: swipe)
        )
    }

    private func wheelMapping(
        _ direction: Mapping.ScrollDirection,
        whileHeld: [Int] = [],
        action: Action
    ) -> Mapping {
        .init(
            trigger: .init(input: .wheel(direction), whileHeld: whileHeld.map(Button.mouse)),
            action: action
        )
    }

    private func ms(_ milliseconds: UInt64) -> UInt64 {
        milliseconds * 1_000_000
    }
}
