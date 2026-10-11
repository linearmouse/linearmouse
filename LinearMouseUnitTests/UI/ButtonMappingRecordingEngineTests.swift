// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ButtonMappingRecordingEngineTests: XCTestCase {
    private typealias Mapping = Scheme.Buttons.Mapping

    func testRecordsSwipeAtConfiguredThreshold() {
        for threshold in [20.0, 100.0] {
            var recorder = ButtonMappingRecordingEngine(policy: .configured(by: .init(threshold: threshold)))
            recorder.buttonDown(.mouse(1), modifierFlags: [], at: ms(0))
            recorder.pointerMoved(deltaX: threshold - 1, deltaY: 0, at: ms(10))
            XCTAssertNil(recorder.snapshot.recognition)
            recorder.pointerMoved(deltaX: 1, deltaY: 0, at: ms(20))
            XCTAssertEqual(recorder.snapshot.recognition, .swipe(.right))
        }
    }

    func testRecordsShortPress() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [.maskCommand], at: ms(0))
        XCTAssertNil(recorder.snapshot.recognition)
        XCTAssertEqual(recorder.snapshot.mapping?.outcomes?.shortPress, .arg0(.auto))
        recorder.buttonUp(.mouse(4), at: ms(100))

        XCTAssertEqual(recorder.snapshot.recognition, .shortPress)
        XCTAssertTrue(recorder.snapshot.isComplete)
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.modifiers, [.command])
    }

    func testShowsModifiersBeforeTheFirstTriggerInput() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.modifierFlagsChanged([.maskCommand, .maskShift])

        XCTAssertEqual(
            recorder.snapshot.modifierFlags,
            [.maskCommand, .maskShift]
        )
        XCTAssertNil(recorder.snapshot.mapping)
    }

    func testLongPressUpdatesLiveAtGlobalThreshold() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.advance(to: ms(499))
        XCTAssertNil(recorder.snapshot.recognition)
        recorder.advance(to: ms(500))

        XCTAssertEqual(recorder.snapshot.recognition, .longPress)
        XCTAssertEqual(recorder.snapshot.mapping?.outcomes?.longPress, .arg0(.auto))
        XCTAssertNil(recorder.snapshot.mapping?.outcomes?.shortPress)
    }

    func testRecordsTwoButtonChordWithinWindow() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.buttonDown(.mouse(5), modifierFlags: [], at: ms(50))

        XCTAssertTrue(recorder.snapshot.isChord)
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.input, .button(.mouse(4)))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.simultaneous, [.mouse(5)])
    }

    func testRecordsLateSecondButtonAsOrderedHeldTrigger() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.buttonDown(.mouse(5), modifierFlags: [], at: ms(100))

        XCTAssertFalse(recorder.snapshot.isChord)
        XCTAssertTrue(recorder.snapshot.isOrdered)
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.input, .button(.mouse(5)))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.whileHeld, [.mouse(4)])
        XCTAssertNil(recorder.snapshot.mapping?.trigger?.simultaneous)
    }

    func testOrderedTriggerCanBeAChord() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.buttonDown(.mouse(5), modifierFlags: [], at: ms(100))
        recorder.buttonDown(.mouse(6), modifierFlags: [], at: ms(140))

        XCTAssertTrue(recorder.snapshot.isOrdered)
        XCTAssertTrue(recorder.snapshot.isChord)
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.input, .button(.mouse(5)))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.simultaneous, [.mouse(6)])
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.whileHeld, [.mouse(4)])
    }

    func testOrderedTriggerLongPressStartsAtSecondButton() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.buttonDown(.mouse(5), modifierFlags: [], at: ms(100))
        recorder.advance(to: ms(599))
        XCTAssertNil(recorder.snapshot.recognition)
        recorder.advance(to: ms(600))

        XCTAssertEqual(recorder.snapshot.recognition, .longPress)
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.input, .button(.mouse(5)))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.whileHeld, [.mouse(4)])
    }

    func testOrderedInputCanReplaceAProvisionalLongPress() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.advance(to: ms(500))
        XCTAssertEqual(recorder.snapshot.recognition, .longPress)

        recorder.buttonDown(.mouse(5), modifierFlags: [], at: ms(700))

        XCTAssertNil(recorder.snapshot.recognition)
        XCTAssertTrue(recorder.snapshot.isOrdered)
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.input, .button(.mouse(5)))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.whileHeld, [.mouse(4)])
        XCTAssertNotNil(recorder.snapshot.mapping?.outcomes?.shortPress)
        XCTAssertNil(recorder.snapshot.mapping?.outcomes?.longPress)
    }

    func testOrderedTriggerCanRecordSwipeWithModifiers() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [.maskCommand], at: ms(0))
        recorder.buttonDown(.mouse(5), modifierFlags: [.maskCommand], at: ms(100))
        recorder.pointerMoved(deltaX: -60, deltaY: 0, at: ms(150))

        XCTAssertEqual(recorder.snapshot.recognition, .swipe(.left))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.input, .button(.mouse(5)))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.whileHeld, [.mouse(4)])
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.modifiers, [.command])
        XCTAssertEqual(recorder.snapshot.mapping?.outcomes?.swipe?.left, .arg0(.auto))
    }

    func testShowsWhenHoldingCanBecomeAnOrderedTrigger() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.advance(to: ms(79))
        XCTAssertFalse(recorder.snapshot.isReadyForOrderedInput)
        recorder.advance(to: ms(80))

        XCTAssertTrue(recorder.snapshot.isReadyForOrderedInput)
    }

    func testEitherReleaseOrderCompletesOrderedShortPress() {
        var prefixFirst = ButtonMappingRecordingEngine()
        prefixFirst.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        prefixFirst.buttonDown(.mouse(5), modifierFlags: [], at: ms(100))
        prefixFirst.buttonUp(.mouse(4), at: ms(150))
        prefixFirst.buttonUp(.mouse(5), at: ms(200))

        var triggerFirst = ButtonMappingRecordingEngine()
        triggerFirst.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        triggerFirst.buttonDown(.mouse(5), modifierFlags: [], at: ms(100))
        triggerFirst.buttonUp(.mouse(5), at: ms(150))
        triggerFirst.buttonUp(.mouse(4), at: ms(200))

        for snapshot in [prefixFirst.snapshot, triggerFirst.snapshot] {
            XCTAssertEqual(snapshot.recognition, .shortPress)
            XCTAssertTrue(snapshot.isComplete)
            XCTAssertEqual(snapshot.mapping?.trigger?.input, .button(.mouse(5)))
            XCTAssertEqual(snapshot.mapping?.trigger?.whileHeld, [.mouse(4)])
        }
    }

    func testRecordsEachSwipeDirection() {
        let movements: [(Double, Double, ButtonMappingEngine.SwipeDirection)] = [
            (60, 0, .right),
            (-60, 0, .left),
            (0, 60, .down),
            (0, -60, .up)
        ]

        for (deltaX, deltaY, direction) in movements {
            var recorder = ButtonMappingRecordingEngine()
            recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
            recorder.pointerMoved(deltaX: deltaX, deltaY: deltaY, at: ms(100))

            XCTAssertEqual(recorder.snapshot.recognition, .swipe(direction))
            XCTAssertNotNil(swipeAction(in: recorder.snapshot.mapping, direction: direction))
        }
    }

    func testShowsMovementDirectionBeforeSwipeThreshold() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.pointerMoved(deltaX: -10, deltaY: 1, at: ms(100))

        XCTAssertEqual(recorder.snapshot.movementDirection, .left)
        XCTAssertNil(recorder.snapshot.recognition)
    }

    func testSwipeCanReplaceProvisionalLongPressWhileButtonRemainsHeld() {
        var recorder = ButtonMappingRecordingEngine()
        let button: Mapping.Button = .logitechControl(.init(controlID: 0xC3))

        recorder.buttonDown(button, modifierFlags: [], at: ms(0))
        recorder.advance(to: ms(500))
        XCTAssertEqual(recorder.snapshot.recognition, .longPress)

        recorder.pointerMoved(deltaX: 0, deltaY: -30, at: ms(700))
        XCTAssertEqual(recorder.snapshot.recognition, .longPress)
        XCTAssertEqual(recorder.snapshot.movementDirection, .up)
        recorder.pointerMoved(deltaX: 0, deltaY: -30, at: ms(800))

        XCTAssertEqual(recorder.snapshot.recognition, .swipe(.up))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.input, .button(button))
        XCTAssertEqual(recorder.snapshot.mapping?.outcomes?.swipe?.up, .arg0(.auto))
        XCTAssertNil(recorder.snapshot.mapping?.outcomes?.longPress)
        XCTAssertFalse(recorder.snapshot.isComplete)

        recorder.buttonUp(button, at: ms(900))
        XCTAssertEqual(recorder.snapshot.recognition, .swipe(.up))
        XCTAssertTrue(recorder.snapshot.isComplete)
    }

    func testMovementBelowSwipeThresholdPreservesLongPressOnRelease() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.pointerMoved(deltaX: 30, deltaY: 0, at: ms(700))
        recorder.buttonUp(.mouse(4), at: ms(900))

        XCTAssertEqual(recorder.snapshot.recognition, .longPress)
        XCTAssertEqual(recorder.snapshot.mapping?.outcomes?.longPress, .arg0(.auto))
        XCTAssertTrue(recorder.snapshot.isComplete)
    }

    func testCompletedLongPressCannotBecomeSwipe() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.buttonUp(.mouse(4), at: ms(600))
        let completed = recorder.snapshot
        recorder.pointerMoved(deltaX: 100, deltaY: 0, at: ms(700))

        XCTAssertEqual(recorder.snapshot, completed)
        XCTAssertEqual(recorder.snapshot.recognition, .longPress)
        XCTAssertTrue(recorder.snapshot.isComplete)
    }

    func testCombinedLongPressCanBecomeSwipeWhileAllButtonsRemainHeld() {
        for secondPressTime: UInt64 in [40, 100] {
            var recorder = ButtonMappingRecordingEngine()
            recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
            recorder.buttonDown(.mouse(5), modifierFlags: [], at: ms(secondPressTime))
            recorder.advance(to: ms(600))
            XCTAssertEqual(recorder.snapshot.recognition, .longPress)

            recorder.pointerMoved(deltaX: 60, deltaY: 0, at: ms(700))

            XCTAssertEqual(recorder.snapshot.recognition, .swipe(.right))
            XCTAssertEqual(recorder.snapshot.isChord, secondPressTime == 40)
            XCTAssertEqual(recorder.snapshot.isOrdered, secondPressTime == 100)
            XCTAssertEqual(recorder.snapshot.mapping?.outcomes?.swipe?.right, .arg0(.auto))
        }
    }

    func testCombinedLongPressCannotBecomeSwipeAfterEitherButtonIsReleased() {
        for secondPressTime: UInt64 in [40, 100] {
            for releasedButton: Mapping.Button in [.mouse(4), .mouse(5)] {
                var recorder = ButtonMappingRecordingEngine()
                recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
                recorder.buttonDown(.mouse(5), modifierFlags: [], at: ms(secondPressTime))
                recorder.advance(to: ms(600))
                recorder.pointerMoved(deltaX: 30, deltaY: 0, at: ms(650))
                recorder.buttonUp(releasedButton, at: ms(700))
                let released = recorder.snapshot
                XCTAssertEqual(released.recognition, .longPress)
                XCTAssertFalse(released.isComplete)

                recorder.pointerMoved(deltaX: 30, deltaY: 0, at: ms(800))

                XCTAssertEqual(recorder.snapshot, released)
                let remainingButton: Mapping.Button = releasedButton == .mouse(4) ? .mouse(5) : .mouse(4)
                recorder.buttonUp(remainingButton, at: ms(900))
                XCTAssertEqual(recorder.snapshot.recognition, .longPress)
                XCTAssertEqual(recorder.snapshot.mapping?.outcomes?.longPress, .arg0(.auto))
                XCTAssertNil(recorder.snapshot.mapping?.outcomes?.swipe)
                XCTAssertTrue(recorder.snapshot.isComplete)
            }
        }
    }

    func testRecognizedSwipeCannotBeReplacedByLaterMovement() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.pointerMoved(deltaX: 60, deltaY: 0, at: ms(100))
        recorder.pointerMoved(deltaX: -120, deltaY: 0, at: ms(700))
        recorder.buttonUp(.mouse(4), at: ms(900))

        XCTAssertEqual(recorder.snapshot.recognition, .swipe(.right))
        XCTAssertTrue(recorder.snapshot.isComplete)
    }

    func testRecordsPlainWheelImmediately() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.wheel(.left, modifierFlags: [.maskShift], at: ms(0))

        XCTAssertEqual(recorder.snapshot.recognition, .wheel(.left))
        XCTAssertTrue(recorder.snapshot.isComplete)
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.input, .wheel(.left))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.modifiers, [.shift])
    }

    func testRecordsWheelWhileButtonIsHeldAndCompletesAfterRelease() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.wheel(.down, modifierFlags: [], at: ms(100))

        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.input, .wheel(.down))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.whileHeld, [.mouse(4)])
        XCTAssertFalse(recorder.snapshot.isComplete)

        recorder.buttonUp(.mouse(4), at: ms(120))
        XCTAssertTrue(recorder.snapshot.isComplete)
    }

    func testWheelBeforeLongPressWins() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.wheel(.up, modifierFlags: [], at: ms(499))
        recorder.advance(to: ms(600))

        XCTAssertEqual(recorder.snapshot.recognition, .wheel(.up))
    }

    func testWheelCanReplaceProvisionalLongPressWhileButtonRemainsHeld() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.advance(to: ms(500))
        XCTAssertEqual(recorder.snapshot.recognition, .longPress)

        recorder.wheel(.down, modifierFlags: [], at: ms(700))

        XCTAssertEqual(recorder.snapshot.recognition, .wheel(.down))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.input, .wheel(.down))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.whileHeld, [.mouse(4)])
        XCTAssertFalse(recorder.snapshot.isComplete)

        recorder.buttonUp(.mouse(4), at: ms(750))
        XCTAssertTrue(recorder.snapshot.isComplete)
    }

    func testCommittedSwipeCannotBecomeWheelGesture() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.pointerMoved(deltaX: 60, deltaY: 0, at: ms(100))
        recorder.wheel(.up, modifierFlags: [], at: ms(120))

        XCTAssertEqual(recorder.snapshot.recognition, .swipe(.right))
        XCTAssertEqual(recorder.snapshot.mapping?.trigger?.input, .button(.mouse(4)))
    }

    func testChordReleaseCommitsShortPressBeforeLaterMovement() {
        var recorder = ButtonMappingRecordingEngine()

        recorder.buttonDown(.mouse(4), modifierFlags: [], at: ms(0))
        recorder.buttonDown(.mouse(5), modifierFlags: [], at: ms(40))
        recorder.buttonUp(.mouse(5), at: ms(100))
        recorder.pointerMoved(deltaX: 60, deltaY: 0, at: ms(120))

        XCTAssertEqual(recorder.snapshot.recognition, .shortPress)
        XCTAssertNotNil(recorder.snapshot.mapping?.outcomes?.shortPress)
        XCTAssertNil(recorder.snapshot.mapping?.outcomes?.swipe)
    }

    private func swipeAction(
        in mapping: Mapping?,
        direction: ButtonMappingEngine.SwipeDirection
    ) -> Mapping.Action? {
        switch direction {
        case .up:
            return mapping?.outcomes?.swipe?.up
        case .down:
            return mapping?.outcomes?.swipe?.down
        case .left:
            return mapping?.outcomes?.swipe?.left
        case .right:
            return mapping?.outcomes?.swipe?.right
        }
    }

    private func ms(_ milliseconds: UInt64) -> UInt64 {
        milliseconds * 1_000_000
    }
}
