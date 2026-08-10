// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import KeyKit
@testable import LinearMouse
import XCTest

private final class ButtonMappingTestTimerScheduler {
    private final class ScheduledTimer {
        var deadline: UInt64
        var handler: () -> Void
        var active = true

        init(deadline: UInt64, handler: @escaping () -> Void) {
            self.deadline = deadline
            self.handler = handler
        }
    }

    private var timers = [ScheduledTimer]()
    private(set) var now: UInt64 = 0

    func schedule(
        interval: TimeInterval,
        handler: @escaping () -> Void
    ) -> ButtonMappingTransformer.TimerToken {
        let timer = ScheduledTimer(
            deadline: now + UInt64(interval * 1_000_000_000),
            handler: handler
        )
        timers.append(timer)
        return .init {
            timer.active = false
        }
    }

    func advance(to timestamp: UInt64) {
        while let timer = timers
            .filter(\.active)
            .filter({ $0.deadline <= timestamp })
            .min(by: { $0.deadline < $1.deadline }) {
            now = timer.deadline
            timer.active = false
            timer.handler()
        }
        now = timestamp
    }
}

private final class ButtonMappingTestKeySimulator: KeySimulating {
    enum Event: Equatable {
        case down([Key])
        case up([Key])
        case press([Key])
        case reset
    }

    private(set) var events = [Event]()

    func down(keys: [Key], tap _: CGEventTapLocation?) throws {
        events.append(.down(keys))
    }

    func up(keys: [Key], tap _: CGEventTapLocation?) throws {
        events.append(.up(keys))
    }

    func press(keys: [Key], tap _: CGEventTapLocation?) throws {
        events.append(.press(keys))
    }

    func press(keys: [Key], modifierFlags _: CGEventFlags, tap _: CGEventTapLocation?) throws {
        events.append(.press(keys))
    }

    func press(
        keys: [Key],
        modifierFlags _: CGEventFlags,
        restoringModifierFlags _: CGEventFlags,
        tap _: CGEventTapLocation?
    ) throws {
        events.append(.press(keys))
    }

    func reset() {
        events.append(.reset)
    }

    func modifiedCGEventFlags(of _: CGEvent) -> CGEventFlags? {
        nil
    }
}

final class ButtonMappingTransformerTests: XCTestCase {
    private typealias Mapping = Scheme.Buttons.Mapping

    override func setUp() {
        super.setUp()
        SettingsState.shared.endButtonMappingRecording()
    }

    override func tearDown() {
        SettingsState.shared.endButtonMappingRecording()
        super.tearDown()
    }

    func testShortPressConsumesOriginalButtonEvents() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var replayed = [CGEventType]()
        let transformer = makeTransformer(
            mappings: [buttonMapping(short: .arg0(.none))],
            scheduler: scheduler
        ) { replayed.append($0.type) }

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        scheduler.advance(to: ms(100))
        XCTAssertNil(try transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))
        XCTAssertEqual(replayed, [])
    }

    func testPendingSideButtonDoesNotDelayUnrelatedPrimaryDrag() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var replayed = [CGEventType]()
        let transformer = makeTransformer(
            mappings: [buttonMapping(button: 4, long: .arg0(.none))],
            scheduler: scheduler
        ) { replayed.append($0.type) }

        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertNotNil(try transformer.transform(
            buttonEvent(button: 0, pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertNotNil(try transformer.transform(
            draggedEvent(button: 0, deltaX: 3),
            in: .init(device: nil)
        ))
        XCTAssertNotNil(try transformer.transform(
            buttonEvent(button: 0, pressed: false),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: false),
            in: .init(device: nil)
        ))

        XCTAssertEqual(replayed, [.otherMouseDown, .otherMouseUp])
    }

    func testInteractionStartedBeforeRecordingDrainsWithoutClaimingNewButtons() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let transformer = makeTransformer(
            mappings: [buttonMapping(button: 4, short: .arg0(.none))],
            scheduler: scheduler
        )

        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: true),
            in: .init(device: nil)
        ))
        SettingsState.shared.beginButtonMappingRecording(sessionID: UUID())

        XCTAssertNotNil(try transformer.transform(
            buttonEvent(button: 5, pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: false),
            in: .init(device: nil)
        ))
        XCTAssertFalse(transformer.hasActiveInteraction)
    }

    func testLogitechInteractionStartedBeforeRecordingDrainsOnRelease() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let identity = LogitechControlIdentity(controlID: 0xC4)
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(identity))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        SettingsState.shared.beginButtonMappingRecording(sessionID: UUID())

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: false)),
            .handled
        )
        XCTAssertFalse(transformer.hasActiveInteraction)
    }

    func testGestureButtonWinsOverShortPressMappingAfterDrag() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let gestureTransformer = makeGestureTransformer(button: .mouse(4))
        let transformer = makeTransformer(
            mappings: [buttonMapping(short: .arg1(.keyPress([.a])))],
            scheduler: scheduler,
            keySimulator: keySimulator,
            gestureTransformer: gestureTransformer
        )

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        XCTAssertNil(try transformer.transform(
            draggedEvent(button: 4, deltaX: 10),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))

        XCTAssertEqual(keySimulator.events, [])
    }

    func testImmediatePressMappingCancelsCompetingGestureTracking() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let gestureTransformer = makeGestureTransformer(button: .mouse(4))
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: .init(action: .arg0(.none), behavior: .perform))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            gestureTransformer: gestureTransformer
        )

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))

        XCTAssertFalse(gestureTransformer.hasActiveInteraction)
        XCTAssertTrue(transformer.hasActiveInteraction)
    }

    func testLongPressMappingCancelsCompetingGestureTrackingAtDeadline() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let gestureTransformer = makeGestureTransformer(button: .mouse(4))
        let transformer = makeTransformer(
            mappings: [buttonMapping(long: .arg0(.none))],
            scheduler: scheduler,
            gestureTransformer: gestureTransformer
        )

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        XCTAssertTrue(gestureTransformer.hasActiveInteraction)

        scheduler.advance(to: ms(500))

        XCTAssertFalse(gestureTransformer.hasActiveInteraction)
        XCTAssertTrue(transformer.hasActiveInteraction)
    }

    func testImmediateRemapCancelsCompetingGestureAndOwnsCompleteStream() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let gestureTransformer = makeGestureTransformer(button: .mouse(4))
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: .init(action: .arg0(.mouseButtonLeft), behavior: .remap))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            gestureTransformer: gestureTransformer
        )

        let down = try XCTUnwrap(transformer.transform(
            buttonEvent(pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertEqual(down.type, .leftMouseDown)
        XCTAssertEqual(MouseEventView(down).mouseButton, .left)
        XCTAssertFalse(gestureTransformer.hasActiveInteraction)

        let dragged = try XCTUnwrap(transformer.transform(
            draggedEvent(button: 4, deltaX: 10),
            in: .init(device: nil)
        ))
        XCTAssertEqual(dragged.type, .leftMouseDragged)
        XCTAssertEqual(MouseEventView(dragged).mouseButton, .left)

        let up = try XCTUnwrap(transformer.transform(
            buttonEvent(pressed: false),
            in: .init(device: nil)
        ))
        XCTAssertEqual(up.type, .leftMouseUp)
        XCTAssertEqual(MouseEventView(up).mouseButton, .left)
        XCTAssertFalse(transformer.hasActiveInteraction)
    }

    func testGestureCleanupDoesNotDiscardIndependentFallbackStream() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var deliveredEvents = [CGEvent]()
        let transformer = makeTransformer(
            mappings: [
                buttonMapping(button: 4, long: .arg0(.none)),
                buttonMapping(button: 5, long: .arg0(.none))
            ],
            scheduler: scheduler,
            gestureTransformer: makeGestureTransformer(button: .mouse(4))
        ) { deliveredEvents.append($0) }

        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: true),
            in: .init(device: nil)
        ))
        scheduler.advance(to: ms(500))

        scheduler.advance(to: ms(600))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 5, pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            draggedEvent(button: 4, deltaX: 10),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: false),
            in: .init(device: nil)
        ))

        scheduler.advance(to: ms(700))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 5, pressed: false),
            in: .init(device: nil)
        ))

        XCTAssertEqual(deliveredEvents.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(
            deliveredEvents.map { MouseEventView($0).mouseButton },
            [CGMouseButton(rawValue: 5), CGMouseButton(rawValue: 5)]
        )
    }

    func testShortPressMappingRemainsGestureButtonClickFallback() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let transformer = makeTransformer(
            mappings: [buttonMapping(short: .arg1(.keyPress([.a])))],
            scheduler: scheduler,
            keySimulator: keySimulator,
            gestureTransformer: makeGestureTransformer(button: .mouse(4))
        )

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        XCTAssertNil(try transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))

        let actionPerformed = expectation(description: "short press action performed")
        DispatchQueue.main.async {
            XCTAssertEqual(keySimulator.events, [.press([.a]), .reset])
            actionPerformed.fulfill()
        }
        wait(for: [actionPerformed], timeout: 1)
    }

    func testUndefinedShortPressReplaysBalancedClick() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var replayed = [CGEventType]()
        let transformer = makeTransformer(
            mappings: [buttonMapping(long: .arg0(.none))],
            scheduler: scheduler
        ) { replayed.append($0.type) }

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        scheduler.advance(to: ms(100))
        XCTAssertNil(try transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))

        XCTAssertEqual(replayed, [.otherMouseDown, .otherMouseUp])
    }

    func testUndefinedShortPressRebuildsFreshClickAfterCallbackAndDropsDrag() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var scheduledReplay: (() -> Void)?
        var scheduledRelease: (() -> Void)?
        var scheduledReleaseDelay: TimeInterval?
        var replayed = [CGEvent]()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(1)), modifiers: [.shift]),
            outcomes: .init(longPress: .arg0(.none))
        )
        let transformer = ButtonMappingTransformer(
            mappings: [mapping],
            scheduleTimer: scheduler.schedule,
            monotonicClock: { scheduler.now },
            syntheticClickScheduler: { scheduledReplay = $0 },
            syntheticClickReleaseScheduler: { delay, handler in
                scheduledReleaseDelay = delay
                scheduledRelease = handler
            },
            syntheticClickEventSink: { replayed.append($0) }
        )

        let down = try buttonEvent(button: 1, pressed: true)
        down.location = .init(x: 120, y: 80)
        down.flags = [.maskShift]
        down.setIntegerValueField(.mouseEventClickState, value: 2)
        let drag = try draggedEvent(button: 1, deltaX: 3)
        let up = try buttonEvent(button: 1, pressed: false)

        XCTAssertNil(transformer.transform(down, in: .init(device: nil)))
        XCTAssertNil(transformer.transform(drag, in: .init(device: nil)))
        XCTAssertNil(transformer.transform(up, in: .init(device: nil)))
        XCTAssertTrue(replayed.isEmpty)

        try XCTUnwrap(scheduledReplay)()

        XCTAssertEqual(replayed.map(\.type), [.rightMouseDown])
        XCTAssertEqual(try XCTUnwrap(scheduledReleaseDelay), 0.015, accuracy: 0.000001)

        try XCTUnwrap(scheduledRelease)()

        XCTAssertEqual(replayed.map(\.type), [.rightMouseDown, .rightMouseUp])
        XCTAssertNotIdentical(replayed[0], down)
        XCTAssertNotIdentical(replayed[1], up)
        XCTAssertEqual(replayed.map { MouseEventView($0).mouseButton }, [.right, .right])
        XCTAssertEqual(replayed.map(\.location), [down.location, down.location])
        XCTAssertEqual(replayed.map(\.flags), [down.flags, down.flags])
        XCTAssertEqual(
            replayed.map { $0.getIntegerValueField(.mouseEventClickState) },
            [2, 2]
        )
        XCTAssertTrue(replayed.allSatisfy(\.isLinearMouseSyntheticEvent))
    }

    func testCommittedLongPressDoesNotLeakIntoIndependentFallbackStream() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var deliveredEvents = [CGEvent]()
        let transformer = makeTransformer(
            mappings: [
                buttonMapping(button: 4, long: .arg0(.none)),
                buttonMapping(button: 5, long: .arg0(.none))
            ],
            scheduler: scheduler
        ) { deliveredEvents.append($0) }

        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: true),
            in: .init(device: nil)
        ))
        scheduler.advance(to: ms(500))
        XCTAssertNil(try transformer.transform(
            draggedEvent(button: 4, deltaX: 10),
            in: .init(device: nil)
        ))

        scheduler.advance(to: ms(600))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 5, pressed: true),
            in: .init(device: nil)
        ))
        scheduler.advance(to: ms(700))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 5, pressed: false),
            in: .init(device: nil)
        ))

        XCTAssertEqual(deliveredEvents.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(
            deliveredEvents.map { MouseEventView($0).mouseButton },
            [CGMouseButton(rawValue: 5), CGMouseButton(rawValue: 5)]
        )

        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: false),
            in: .init(device: nil)
        ))
        XCTAssertEqual(deliveredEvents.map(\.type), [.otherMouseDown, .otherMouseUp])
    }

    func testIndependentDeferredShortPressesCanOverlap() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let transformer = makeTransformer(
            mappings: [
                buttonMapping(button: 4, short: .arg1(.keyPress([.a]))),
                buttonMapping(button: 5, short: .arg1(.keyPress([.b])))
            ],
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 5, pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 5, pressed: false),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: false),
            in: .init(device: nil)
        ))

        let actionsPerformed = expectation(description: "both short press actions performed")
        DispatchQueue.main.async {
            XCTAssertEqual(keySimulator.events, [
                .press([.b]),
                .reset,
                .press([.a]),
                .reset
            ])
            actionsPerformed.fulfill()
        }
        wait(for: [actionsPerformed], timeout: 1)
        XCTAssertFalse(transformer.hasActiveInteraction)
    }

    func testIndependentFallbackBufferSurvivesAnotherShortPressCommit() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var deliveredEvents = [CGEvent]()
        let transformer = makeTransformer(
            mappings: [
                buttonMapping(button: 4, long: .arg0(.none)),
                buttonMapping(button: 5, short: .arg0(.none))
            ],
            scheduler: scheduler
        ) { deliveredEvents.append($0) }

        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 5, pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 5, pressed: false),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: false),
            in: .init(device: nil)
        ))

        XCTAssertEqual(deliveredEvents.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(
            deliveredEvents.map { MouseEventView($0).mouseButton },
            [CGMouseButton(rawValue: 4), CGMouseButton(rawValue: 4)]
        )
        XCTAssertFalse(transformer.hasActiveInteraction)
    }

    func testIndependentLongPressDeadlinesFireWhileBothButtonsRemainHeld() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let transformer = makeTransformer(
            mappings: [
                buttonMapping(button: 4, long: .arg1(.keyPress([.a]))),
                buttonMapping(button: 5, long: .arg1(.keyPress([.b])))
            ],
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: true),
            in: .init(device: nil)
        ))
        scheduler.advance(to: ms(10))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 5, pressed: true),
            in: .init(device: nil)
        ))

        scheduler.advance(to: ms(500))
        scheduler.advance(to: ms(510))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: false),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 5, pressed: false),
            in: .init(device: nil)
        ))

        let actionsPerformed = expectation(description: "both long press actions performed")
        DispatchQueue.main.async {
            XCTAssertEqual(keySimulator.events, [
                .press([.a]),
                .reset,
                .press([.b]),
                .reset
            ])
            actionsPerformed.fulfill()
        }
        wait(for: [actionsPerformed], timeout: 1)
        XCTAssertFalse(transformer.hasActiveInteraction)
    }

    func testHeldWheelMappingWinsAcrossIndependentRecognitionLanes() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        var deliveredEvents = [CGEvent]()
        let transformer = makeTransformer(
            mappings: [
                buttonMapping(button: 4, long: .arg0(.none)),
                buttonMapping(button: 5, long: .arg0(.none)),
                Mapping(trigger: .init(input: .wheel(.up)), action: .arg1(.keyPress([.a]))),
                Mapping(
                    trigger: .init(input: .wheel(.up), whileHeld: [.mouse(5)]),
                    action: .arg1(.keyPress([.b]))
                )
            ],
            scheduler: scheduler,
            keySimulator: keySimulator
        ) { deliveredEvents.append($0) }

        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 5, pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(scrollEvent(vertical: 1), in: .init(device: nil)))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 5, pressed: false),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 4, pressed: false),
            in: .init(device: nil)
        ))

        let actionPerformed = expectation(description: "held wheel action performed")
        DispatchQueue.main.async {
            XCTAssertEqual(keySimulator.events, [.press([.b]), .reset])
            actionPerformed.fulfill()
        }
        wait(for: [actionPerformed], timeout: 1)
        XCTAssertEqual(deliveredEvents.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(
            deliveredEvents.map { MouseEventView($0).mouseButton },
            [CGMouseButton(rawValue: 4), CGMouseButton(rawValue: 4)]
        )
        XCTAssertFalse(transformer.hasActiveInteraction)
    }

    func testFailedChordReplaysPrefixAtChordDeadline() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var replayed = [CGEventType]()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4)), simultaneous: [.mouse(5)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler
        ) { replayed.append($0.type) }

        XCTAssertNil(try transformer.transform(buttonEvent(button: 4, pressed: true), in: .init(device: nil)))
        scheduler.advance(to: ms(80))
        XCTAssertEqual(replayed, [.otherMouseDown])
        XCTAssertNil(try transformer.transform(buttonEvent(button: 4, pressed: false), in: .init(device: nil)))
        XCTAssertEqual(replayed, [.otherMouseDown, .otherMouseUp])
    }

    func testFailedPrimarySecondaryChordForwardsBalancedIndividualClicks() throws {
        for button in [0, 1] {
            let scheduler = ButtonMappingTestTimerScheduler()
            var delivered = [CGEventType]()
            let mapping = Mapping(
                trigger: .init(input: .button(.mouse(0)), simultaneous: [.mouse(1)]),
                outcomes: .init(shortPress: .arg0(.none))
            )
            let transformer = makeTransformer(
                mappings: [mapping],
                scheduler: scheduler
            ) { delivered.append($0.type) }

            if let event = try transformer.transform(
                buttonEvent(button: button, pressed: true),
                in: .init(device: nil)
            ) {
                delivered.append(event.type)
            }
            scheduler.advance(to: ms(80))
            XCTAssertNil(try transformer.transform(
                buttonEvent(button: button, pressed: false),
                in: .init(device: nil)
            ))

            let mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .left
            XCTAssertEqual(delivered, [
                mouseButton.fixedCGEventType(of: .otherMouseDown),
                mouseButton.fixedCGEventType(of: .otherMouseUp)
            ])
        }
    }

    func testQuickPrimarySecondaryChordFallbackReplaysBalancedIndividualClicks() throws {
        for button in [0, 1] {
            let scheduler = ButtonMappingTestTimerScheduler()
            var delivered = [CGEventType]()
            let mapping = Mapping(
                trigger: .init(input: .button(.mouse(0)), simultaneous: [.mouse(1)]),
                outcomes: .init(shortPress: .arg0(.none))
            )
            let transformer = makeTransformer(
                mappings: [mapping],
                scheduler: scheduler
            ) { delivered.append($0.type) }

            XCTAssertNil(try transformer.transform(
                buttonEvent(button: button, pressed: true),
                in: .init(device: nil)
            ))
            scheduler.advance(to: ms(40))
            XCTAssertNil(try transformer.transform(
                buttonEvent(button: button, pressed: false),
                in: .init(device: nil)
            ))

            let mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .left
            XCTAssertEqual(delivered, [
                mouseButton.fixedCGEventType(of: .otherMouseDown),
                mouseButton.fixedCGEventType(of: .otherMouseUp)
            ])
        }
    }

    func testFailedPrimarySecondaryChordForwardsDragAndReleaseThroughDeferredSink() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var fallbackEvents = [CGEventType]()
        var deferredEvents = [CGEventType]()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(0)), simultaneous: [.mouse(1)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler
        ) { fallbackEvents.append($0.type) }
        let context = EventTransformerContext(device: nil) {
            deferredEvents.append($0.type)
        }

        XCTAssertNil(try transformer.transform(buttonEvent(button: 0, pressed: true), in: context))
        scheduler.advance(to: ms(80))
        XCTAssertEqual(deferredEvents, [.leftMouseDown])

        XCTAssertNil(try transformer.transform(draggedEvent(button: 0, deltaX: 3), in: context))
        XCTAssertNil(try transformer.transform(buttonEvent(button: 0, pressed: false), in: context))

        XCTAssertEqual(deferredEvents, [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        XCTAssertEqual(fallbackEvents, [])
    }

    func testCompletedChordDoesNotReplayEitherButton() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var replayed = [CGEventType]()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4)), simultaneous: [.mouse(5)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler
        ) { replayed.append($0.type) }

        XCTAssertNil(try transformer.transform(buttonEvent(button: 4, pressed: true), in: .init(device: nil)))
        scheduler.advance(to: ms(30))
        XCTAssertNil(try transformer.transform(buttonEvent(button: 5, pressed: true), in: .init(device: nil)))
        scheduler.advance(to: ms(50))
        XCTAssertNil(try transformer.transform(buttonEvent(button: 5, pressed: false), in: .init(device: nil)))
        XCTAssertNil(try transformer.transform(buttonEvent(button: 4, pressed: false), in: .init(device: nil)))
        XCTAssertEqual(replayed, [])
    }

    func testWheelMappingConsumesPhysicalEventButIgnoresSyntheticAndMomentum() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let mapping = Mapping(trigger: .init(input: .wheel(.up)), action: .arg0(.none))
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertNil(try transformer.transform(scrollEvent(vertical: 1), in: .init(device: nil)))

        let synthetic = try scrollEvent(vertical: 1)
        synthetic.isLinearMouseSyntheticEvent = true
        XCTAssertNotNil(transformer.transform(synthetic, in: .init(device: nil)))

        let momentum = try scrollEvent(vertical: 1)
        ScrollWheelEventView(momentum).momentumPhase = .begin
        XCTAssertNotNil(transformer.transform(momentum, in: .init(device: nil)))
    }

    func testHorizontalWheelUsesDominantAxis() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let mapping = Mapping(trigger: .init(input: .wheel(.left)), action: .arg0(.none))
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertNil(try transformer.transform(
            scrollEvent(horizontal: 3, vertical: 1),
            in: .init(device: nil)
        ))
        XCTAssertNotNil(try transformer.transform(
            scrollEvent(horizontal: -3, vertical: 1),
            in: .init(device: nil)
        ))
    }

    func testSwappedPrimaryButtonMatchesItsRecordedLogicalButton() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(1))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            swapsPrimaryAndSecondaryButtons: true
        )

        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 0, pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 0, pressed: false),
            in: .init(device: nil)
        ))
    }

    func testLogitechQuickReleaseAllowsDeferredFallback() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let identity = LogitechControlIdentity(controlID: 0xC4)
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(identity))),
            outcomes: .init(longPress: .arg0(.none))
        )
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        scheduler.advance(to: ms(100))
        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: false)),
            .handledAllowingSyntheticFallback
        )
    }

    func testLogitechLongPressSuppressesDeferredFallback() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let identity = LogitechControlIdentity(controlID: 0xC4)
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(identity))),
            outcomes: .init(longPress: .arg0(.none))
        )
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        scheduler.advance(to: ms(500))
        XCTAssertEqual(transformer.handleLogitechControlEvent(logitech(identity, pressed: false)), .handled)
    }

    func testCancelingPendingLogitechPressDoesNotPerformShortPress() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let identity = LogitechControlIdentity(controlID: 0xC4)
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(identity))),
            outcomes: .init(shortPress: .arg1(.keyPress([.a])))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        XCTAssertTrue(transformer.hasActiveInteraction)

        XCTAssertTrue(transformer.cancelLogitechControlInteraction(logitech(identity, pressed: false)))
        XCTAssertFalse(transformer.hasActiveInteraction)
        scheduler.advance(to: ms(1000))
        XCTAssertEqual(keySimulator.events, [])
    }

    func testCancelingCommittedLogitechHoldReleasesHeldKeys() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let identity = LogitechControlIdentity(controlID: 0xC4)
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(identity))),
            outcomes: .init(press: .init(action: .arg1(.keyPress([.a])), behavior: .hold))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        XCTAssertEqual(keySimulator.events, [.down([.a])])

        XCTAssertTrue(transformer.cancelLogitechControlInteraction(logitech(identity, pressed: false)))
        XCTAssertFalse(transformer.hasActiveInteraction)
        XCTAssertEqual(keySimulator.events, [.down([.a]), .up([.a]), .reset])
    }

    func testCancelingLogitechChordReplaysBufferedPhysicalButtonDown() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let identity = LogitechControlIdentity(controlID: 0xC4)
        let mapping = Mapping(
            trigger: .init(
                input: .button(.logitechControl(identity)),
                whileHeld: [.mouse(4)]
            ),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)
        var replayedEvents = [CGEventType]()

        let physicalDown = try buttonEvent(pressed: true)
        XCTAssertNil(transformer.transform(
            physicalDown,
            in: .init(device: nil) { replayedEvents.append($0.type) }
        ))
        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: true)),
            .handledDeferringSyntheticFallback
        )

        XCTAssertTrue(transformer.cancelLogitechControlInteraction(logitech(identity, pressed: false)))
        XCTAssertEqual(replayedEvents, [.otherMouseDown])
        XCTAssertFalse(transformer.hasActiveInteraction)

        XCTAssertNotNil(try transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))
    }

    func testLogitechGestureWinsOverShortPressMapping() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let identity = LogitechControlIdentity(controlID: 0xC4)
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(identity))),
            outcomes: .init(shortPress: .arg1(.keyPress([.a])))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            keySimulator: keySimulator,
            gestureTransformer: makeGestureTransformer(button: .logitechControl(identity))
        )

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        XCTAssertNil(try transformer.transform(mouseMovedEvent(deltaX: 10), in: .init(device: nil)))
        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: false)),
            .handled
        )
        XCTAssertEqual(keySimulator.events, [])
    }

    func testSpecificLogitechPressMappingCancelsCompetingGenericGesture() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let generic = LogitechControlIdentity(controlID: 0xC4)
        let specific = LogitechControlIdentity(
            controlID: 0xC4,
            productID: 0x405E,
            serialNumber: "ABC"
        )
        let gestureTransformer = makeGestureTransformer(button: .logitechControl(generic))
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(specific))),
            outcomes: .init(press: .init(action: .arg0(.none), behavior: .perform))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            gestureTransformer: gestureTransformer
        )

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(specific, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        XCTAssertFalse(gestureTransformer.hasActiveInteraction)
        XCTAssertTrue(transformer.hasActiveInteraction)
    }

    func testGenericLogitechControlMatchesDeviceSpecificEventIdentity() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let configured = LogitechControlIdentity(controlID: 0xC4)
        let eventIdentity = LogitechControlIdentity(controlID: 0xC4, productID: 0x405E, serialNumber: "ABC")
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(configured))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(eventIdentity, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        XCTAssertEqual(transformer.handleLogitechControlEvent(logitech(eventIdentity, pressed: false)), .handled)
    }

    func testLogitechIdentityFallbackIsRespected() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let configured = LogitechControlIdentity(controlID: 0xC4, productID: 0x405E, serialNumber: "ABC")
        let eventIdentity = LogitechControlIdentity(controlID: 0xC4, productID: 0x405E)
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(configured))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertEqual(transformer.handleLogitechControlEvent(
            logitech(eventIdentity, pressed: true, allowsIdentityFallback: true)
        ), .handledDeferringSyntheticFallback)
        XCTAssertEqual(transformer.handleLogitechControlEvent(
            logitech(eventIdentity, pressed: false, allowsIdentityFallback: true)
        ), .handled)
    }

    func testDeviceSpecificLogitechMappingWinsOverGenericMapping() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let generic = LogitechControlIdentity(controlID: 0xC4)
        let specific = LogitechControlIdentity(controlID: 0xC4, productID: 0x405E, serialNumber: "ABC")
        let transformer = makeTransformer(
            mappings: [
                Mapping(
                    trigger: .init(input: .button(.logitechControl(generic))),
                    outcomes: .init(press: .init(action: .arg1(.keyPress([.a])), behavior: .hold))
                ),
                Mapping(
                    trigger: .init(input: .button(.logitechControl(specific))),
                    outcomes: .init(press: .init(action: .arg1(.keyPress([.b])), behavior: .hold))
                )
            ],
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(specific, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        XCTAssertEqual(keySimulator.events, [.down([.b])])
        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(specific, pressed: false)),
            .handled
        )
        XCTAssertEqual(keySimulator.events, [.down([.b]), .up([.b]), .reset])
    }

    func testGenericLogitechMappingRemainsAvailableWhenSpecificModifiersDoNotMatch() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let generic = LogitechControlIdentity(controlID: 0xC4)
        let specific = LogitechControlIdentity(controlID: 0xC4, productID: 0x405E, serialNumber: "ABC")
        let transformer = makeTransformer(
            mappings: [
                Mapping(
                    trigger: .init(input: .button(.logitechControl(generic))),
                    outcomes: .init(shortPress: .arg0(.none))
                ),
                Mapping(
                    trigger: .init(
                        input: .button(.logitechControl(specific)),
                        modifiers: [.command]
                    ),
                    outcomes: .init(shortPress: .arg0(.none))
                )
            ],
            scheduler: scheduler
        )

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(specific, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(specific, pressed: false)),
            .handled
        )
    }

    func testHoldPressUsesKeyDownAndKeyUpLifecycle() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: .init(action: .arg1(.keyPress([.a])), behavior: .hold))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        XCTAssertNil(try transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))

        XCTAssertEqual(keySimulator.events, [.down([.a]), .up([.a]), .reset])
    }

    func testDeactivateEndsHeldKeyLifecycle() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: .init(action: .arg1(.keyPress([.a])), behavior: .hold))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        XCTAssertTrue(transformer.hasActiveInteraction)

        transformer.deactivate()

        XCTAssertFalse(transformer.hasActiveInteraction)
        XCTAssertEqual(keySimulator.events, [.down([.a]), .up([.a]), .reset])
    }

    func testDeactivateAfterCompletedHoldDoesNotResetKeySimulatorAgain() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: .init(action: .arg1(.keyPress([.a])), behavior: .hold))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        XCTAssertNil(try transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))
        XCTAssertFalse(transformer.hasActiveInteraction)

        transformer.deactivate()

        XCTAssertEqual(keySimulator.events, [.down([.a]), .up([.a]), .reset])
    }

    func testDeactivateReplaysUncommittedBufferedPress() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var replayedEvents = [CGEventType]()
        let transformer = makeTransformer(
            mappings: [buttonMapping(short: .arg0(.none))],
            scheduler: scheduler
        ) { replayedEvents.append($0.type) }

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        XCTAssertTrue(transformer.hasActiveInteraction)

        transformer.deactivate()

        XCTAssertFalse(transformer.hasActiveInteraction)
        XCTAssertEqual(replayedEvents, [.otherMouseDown])
    }

    func testOverlappingHoldPressesReleaseIndependently() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let mappings = [
            Mapping(
                trigger: .init(input: .button(.mouse(4))),
                outcomes: .init(press: .init(action: .arg1(.keyPress([.command])), behavior: .hold))
            ),
            Mapping(
                trigger: .init(input: .button(.mouse(5))),
                outcomes: .init(press: .init(action: .arg1(.keyPress([.shift])), behavior: .hold))
            )
        ]
        let transformer = makeTransformer(
            mappings: mappings,
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        _ = try transformer.transform(buttonEvent(button: 4, pressed: true), in: .init(device: nil))
        _ = try transformer.transform(buttonEvent(button: 5, pressed: true), in: .init(device: nil))
        _ = try transformer.transform(buttonEvent(button: 5, pressed: false), in: .init(device: nil))
        _ = try transformer.transform(buttonEvent(button: 4, pressed: false), in: .init(device: nil))

        XCTAssertEqual(keySimulator.events, [
            .down([.command]),
            .down([.shift]),
            .up([.shift]),
            .up([.command]),
            .reset
        ])
    }

    func testOverlappingHoldsReferenceCountSharedKeys() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let holdA = Mapping.PressAction(action: .arg1(.keyPress([.a])), behavior: .hold)
        let transformer = makeTransformer(
            mappings: [
                Mapping(
                    trigger: .init(input: .button(.mouse(4))),
                    outcomes: .init(press: holdA)
                ),
                Mapping(
                    trigger: .init(input: .button(.mouse(5))),
                    outcomes: .init(press: holdA)
                )
            ],
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        _ = try transformer.transform(buttonEvent(button: 4, pressed: true), in: .init(device: nil))
        _ = try transformer.transform(buttonEvent(button: 5, pressed: true), in: .init(device: nil))
        XCTAssertEqual(keySimulator.events, [.down([.a])])

        _ = try transformer.transform(buttonEvent(button: 4, pressed: false), in: .init(device: nil))
        XCTAssertEqual(keySimulator.events, [.down([.a])])

        _ = try transformer.transform(buttonEvent(button: 5, pressed: false), in: .init(device: nil))
        XCTAssertEqual(keySimulator.events, [.down([.a]), .up([.a]), .reset])
    }

    func testRemapPressRewritesDownDragAndUpStream() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var deferredEvents = [CGEventType]()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: .init(action: .arg0(.mouseButtonLeft), behavior: .remap))
        )
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler) {
            deferredEvents.append($0.type)
        }

        let down = try XCTUnwrap(transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        let dragged = try XCTUnwrap(transformer.transform(
            draggedEvent(button: 4, deltaX: 3),
            in: .init(device: nil)
        ))
        let up = try XCTUnwrap(transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))

        XCTAssertEqual(down.type, .leftMouseDown)
        XCTAssertEqual(dragged.type, .leftMouseDragged)
        XCTAssertEqual(up.type, .leftMouseUp)
        XCTAssertEqual(MouseEventView(down).mouseButton, .left)
        XCTAssertEqual(MouseEventView(dragged).mouseButton, .left)
        XCTAssertEqual(MouseEventView(up).mouseButton, .left)
        XCTAssertEqual(deferredEvents, [])
    }

    private func makeTransformer(
        mappings: [Mapping],
        scheduler: ButtonMappingTestTimerScheduler,
        swapsPrimaryAndSecondaryButtons: Bool = false,
        keySimulator: KeySimulating? = nil,
        gestureTransformer: GestureButtonTransformer? = nil,
        eventSink: @escaping (CGEvent) -> Void = { _ in }
    ) -> ButtonMappingTransformer {
        .init(
            mappings: mappings,
            swapsPrimaryAndSecondaryButtons: swapsPrimaryAndSecondaryButtons,
            scheduleTimer: scheduler.schedule,
            monotonicClock: { scheduler.now },
            keySimulator: keySimulator,
            gestureTransformer: gestureTransformer,
            eventSink: eventSink,
            syntheticClickScheduler: { $0() },
            syntheticClickReleaseScheduler: { _, handler in handler() },
            syntheticClickEventSink: eventSink
        )
    }

    private func makeGestureTransformer(button: Mapping.Button) -> GestureButtonTransformer {
        GestureButtonTransformer(
            trigger: .init(button: button),
            threshold: 10,
            deadZone: 40,
            cooldownMs: 500,
            actions: .init(right: .some(.none))
        )
    }

    private func buttonMapping(
        button: Int = 4,
        short: Mapping.Action? = nil,
        long: Mapping.Action? = nil
    ) -> Mapping {
        .init(
            trigger: .init(input: .button(.mouse(button))),
            outcomes: .init(shortPress: short, longPress: long)
        )
    }

    private func buttonEvent(button: Int = 4, pressed: Bool) throws -> CGEvent {
        let mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .center
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: mouseButton.fixedCGEventType(of: pressed ? .otherMouseDown : .otherMouseUp),
            mouseCursorPosition: .zero,
            mouseButton: mouseButton
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        return event
    }

    private func draggedEvent(button: Int, deltaX: Double, deltaY: Double = 0) throws -> CGEvent {
        let mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .center
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: mouseButton.fixedCGEventType(of: .otherMouseDragged),
            mouseCursorPosition: .zero,
            mouseButton: mouseButton
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        event.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
        event.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
        return event
    }

    private func mouseMovedEvent(deltaX: Double, deltaY: Double = 0) throws -> CGEvent {
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

    private func scrollEvent(horizontal: Int32 = 0, vertical: Int32 = 0) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ))
    }

    private func logitech(
        _ identity: LogitechControlIdentity,
        pressed: Bool,
        allowsIdentityFallback: Bool = false
    ) -> LogitechEventContext {
        .init(
            device: nil,
            pid: nil,
            display: nil,
            mouseLocation: .zero,
            controlIdentity: identity,
            allowsIdentityFallback: allowsIdentityFallback,
            isPressed: pressed,
            modifierFlags: []
        )
    }

    private func ms(_ milliseconds: UInt64) -> UInt64 {
        milliseconds * 1_000_000
    }
}
