// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ScrollActionRecognizerTests: XCTestCase {
    private typealias Input = ScrollActionRecognizer.Input

    func testUnmatchedMovementAndModifiersCannotBypassCooldownOrReleaseMomentum() {
        let recognizer = ScrollActionRecognizer()
        let input = Input(axis: .vertical, delta: 1, units: .points, hasPhase: true)
        recognizer.updateModifiers(1)
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 0), 1)
        recognizer.discardMovement(on: .vertical)
        recognizer.updateModifiers(0)
        recognizer.endGesture()
        XCTAssertTrue(recognizer.ownsGesture)
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 299_400_000), 0)
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 300_000_000), 1)
        recognizer.beginGesture()
        XCTAssertFalse(recognizer.ownsGesture)
    }

    func testLargeScrollDistanceIsIndependentOfEventSplitting() {
        for pieces in [1, 2, 16, 128] {
            let recognizer = ScrollActionRecognizer()
            let total = (0 ..< pieces).reduce(0) { count, index in
                count + recognizer.consume(
                    Input(axis: .horizontal, delta: 128 / Double(pieces), units: .points),
                    mapping: 0,
                    repeats: true,
                    at: UInt64(index)
                )
            }
            XCTAssertEqual(total, 16)
        }
    }

    func testScrollOutputCoalescesWithoutRepeatingCommands() {
        typealias Action = Scheme.Buttons.Mapping.Action
        XCTAssertEqual(
            Action.arg0(.mouseWheelScrollLeft).coalescingScrollSteps(16),
            .arg1(.mouseWheelScrollLeft(.line(48)))
        )
        XCTAssertEqual(
            Action.arg1(.mouseWheelScrollDown(.pixel(1.5))).coalescingScrollSteps(16),
            .arg1(.mouseWheelScrollDown(.pixel(24)))
        )
        XCTAssertEqual(
            Action.arg1(.mouseWheelScrollUp(.auto)).coalescingScrollSteps(16),
            .arg1(.mouseWheelScrollUp(.line(48)))
        )
        XCTAssertEqual(Action.arg0(.missionControl).coalescingScrollSteps(1), .arg0(.missionControl))
        XCTAssertEqual(
            Action.arg0(.mouseWheelScrollLeft).coalescingScrollSteps(Int.max),
            .arg1(.mouseWheelScrollLeft(.line(Int(Int32.max))))
        )
    }

    func testEventSplittingDoesNotChangeHighResolutionDetentCount() {
        for pieces in [1, 2, 8, 120] {
            let recognizer = ScrollActionRecognizer()
            var count = 0
            for index in 0 ..< pieces * 3 {
                count += recognizer.consume(
                    Input(axis: .vertical, delta: 1 / Double(pieces), units: .detents),
                    mapping: 0,
                    repeats: true,
                    at: UInt64(index) * 1_200_000
                )
            }
            XCTAssertEqual(count, 3, "pieces per detent: \(pieces)")
        }
    }

    func testUnphasedHorizontalMovementRepeatsWithoutWaitingForIdle() {
        let recognizer = ScrollActionRecognizer()
        let input = Input(axis: .horizontal, delta: 1, units: .lines)
        var count = 0
        for index in 0 ..< 30 {
            count += recognizer.consume(
                input,
                mapping: 0,
                repeats: false,
                at: UInt64(index) * 60_000_000
            )
        }
        XCTAssertEqual(count, 6)
        XCTAssertEqual(recognizer.consume(
            input,
            mapping: 0,
            repeats: false,
            at: 2_400_000_000
        ), 1)
    }

    func testGestureBoundariesPreserveCooldownAndContinuousMovementCanRepeat() {
        let recognizer = ScrollActionRecognizer()
        let input = Input(axis: .horizontal, delta: 8, units: .points, hasPhase: true)
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 0), 1)
        recognizer.endGesture()
        XCTAssertTrue(recognizer.ownsGesture)
        recognizer.beginGesture()
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 120_000_000), 0)
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 300_000_000), 1)
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 600_000_000), 1)
    }

    func testContinuousMovementTriggersImmediatelyWithoutRepeating() {
        let recognizer = ScrollActionRecognizer()
        let input = Input(axis: .vertical, delta: 2, units: .points, hasPhase: true)
        let counts = (0 ..< 8).map { index in
            recognizer.consume(
                input,
                mapping: 0,
                repeats: false,
                at: UInt64(index)
            )
        }
        XCTAssertEqual(counts, [1, 0, 0, 0, 0, 0, 0, 0])
    }

    func testDirectionChangesDoNotBypassThrottleForPhasedInput() {
        let recognizer = ScrollActionRecognizer()
        func consume(_ delta: Double, at now: UInt64 = 0) -> Int {
            recognizer.consume(
                Input(axis: .horizontal, delta: delta, units: .points, hasPhase: true),
                mapping: delta > 0 ? 0 : 1,
                repeats: false,
                at: now
            )
        }
        XCTAssertEqual(consume(8), 1)
        XCTAssertEqual(consume(-1), 0)
        XCTAssertEqual(consume(-100), 0)
        XCTAssertEqual(consume(100), 0)
        XCTAssertEqual(consume(-1, at: 300_000_000), 1)
    }

    func testScrollOutputRepeatsByDistanceNotEventCount() {
        for pieces in [1, 2, 8] {
            let recognizer = ScrollActionRecognizer()
            var count = 0
            for index in 0 ..< pieces {
                count += recognizer.consume(
                    Input(axis: .horizontal, delta: 24 / Double(pieces), units: .points),
                    mapping: 0,
                    repeats: true,
                    at: UInt64(index)
                )
            }
            XCTAssertEqual(count, 3)
        }
    }

    func testResetAndMappingChangesDiscardPreviousMovement() {
        let recognizer = ScrollActionRecognizer()
        let input = Input(axis: .horizontal, delta: 4, units: .points)
        XCTAssertEqual(recognizer.consume(
            input,
            mapping: 0,
            repeats: true,
            at: 0
        ), 0)
        XCTAssertEqual(recognizer.consume(
            input,
            mapping: 1,
            repeats: true,
            at: 1
        ), 0)
        XCTAssertEqual(recognizer.consume(
            input,
            mapping: 1,
            repeats: true,
            at: 2
        ), 1)
        recognizer.reset()
        XCTAssertFalse(recognizer.ownsGesture)
        XCTAssertEqual(recognizer.consume(
            input,
            mapping: 1,
            repeats: true,
            at: 3
        ), 0)
    }

    func testAxesAreIndependentAndLargeOrInvalidDeltasCannotQueueBacklog() {
        let recognizer = ScrollActionRecognizer()
        XCTAssertEqual(recognizer.consume(
            Input(axis: .horizontal, delta: 4, units: .points),
            mapping: 0,
            repeats: true,
            at: 0
        ), 0)
        XCTAssertEqual(recognizer.consume(
            Input(axis: .vertical, delta: 4, units: .points),
            mapping: 1,
            repeats: true,
            at: 1
        ), 0)
        XCTAssertEqual(recognizer.consume(
            Input(axis: .vertical, delta: .infinity, units: .points),
            mapping: 1,
            repeats: true,
            at: 2
        ), 0)
        XCTAssertEqual(recognizer.consume(
            Input(axis: .vertical, delta: .greatestFiniteMagnitude, units: .points),
            mapping: 1,
            repeats: true,
            at: 3
        ), 0)
        XCTAssertEqual(recognizer.consume(
            Input(axis: .vertical, delta: 1, units: .points),
            mapping: 1,
            repeats: true,
            at: 4
        ), 0)
    }

    func testTinySlowNavigationStartsImmediatelyAndAllowsSubsequentMovements() {
        for units in [ScrollInput.Units.lines, .points] {
            let recognizer = ScrollActionRecognizer()
            let input = Input(axis: .horizontal, delta: 0.001, units: units)
            XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 0), 1)
            // Each movement can trigger without the old 500 ms quiet period.
            for index in 1 ... 10 {
                XCTAssertEqual(recognizer.consume(
                    input,
                    mapping: 0,
                    repeats: false,
                    at: UInt64(index) * 480_000_000
                ), 1)
            }
            XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 5_520_000_000), 1)
        }
    }

    func testNavigationLatchSurvivesMappingAndUnitChangesDuringStroke() {
        let recognizer = ScrollActionRecognizer()
        XCTAssertEqual(recognizer.consume(
            Input(axis: .horizontal, delta: 0.01, units: .lines),
            mapping: 0,
            repeats: false,
            at: 0
        ), 1)
        XCTAssertEqual(recognizer.consume(
            Input(axis: .horizontal, delta: 80, units: .points),
            mapping: 3,
            repeats: false,
            at: 120_000_000
        ), 0)
    }

    func testModifierChangesPreserveCooldown() {
        let recognizer = ScrollActionRecognizer()
        let input = Input(axis: .horizontal, delta: 0.01, units: .lines)
        recognizer.updateModifiers(0)
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 0), 1)
        recognizer.updateModifiers(0)
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 1), 0)
        recognizer.updateModifiers(1)
        XCTAssertEqual(recognizer.consume(input, mapping: 0, repeats: false, at: 2), 0)
    }

    func testSuppressedEventsDoNotExtendDeadlineAndDirectionsShareCooldown() {
        let recognizer = ScrollActionRecognizer()
        func consume(_ milliseconds: UInt64, delta: Double = 0.001) -> Int {
            recognizer.consume(
                Input(axis: .horizontal, delta: delta, units: .lines),
                mapping: delta > 0 ? 0 : 1,
                repeats: false,
                at: milliseconds * 1_200_000
            )
        }
        XCTAssertEqual(consume(0), 1)
        XCTAssertEqual(consume(100), 0)
        XCTAssertEqual(consume(200, delta: -100), 0)
        XCTAssertEqual(consume(249), 0)
        XCTAssertEqual(consume(250), 1)
        XCTAssertEqual(consume(499), 0)
        XCTAssertEqual(consume(500, delta: -0.001), 1)
        XCTAssertEqual(consume(2000), 1) // No queued actions after stopping.
    }

    func testDiscreteActionsUseSameThrottleForEveryAxisUnitAndPhaseMode() {
        typealias Action = Scheme.Buttons.Mapping.Action
        let actions: [Action] = [
            .arg0(.missionControl), .arg0(.missionControlSpaceLeft), .arg1(.keyPress([])),
            .arg0(.mediaVolumeUp), .arg0(.mediaVolumeDown),
            .arg0(.displayBrightnessUp), .arg0(.displayBrightnessDown),
            .arg0(.keyboardBrightnessUp), .arg0(.keyboardBrightnessDown)
        ]
        for action in actions {
            for axis in [ScrollActionRecognizer.Axis.horizontal, .vertical] {
                for units in [ScrollInput.Units.detents, .lines, .points] {
                    for hasPhase in [false, true] {
                        let recognizer = ScrollActionRecognizer()
                        var counts = [Int]()
                        for time: UInt64 in [0, 10, 100, 249, 250, 260, 500] {
                            counts.append(recognizer.consume(
                                Input(axis: axis, delta: 0.125, units: units, hasPhase: hasPhase),
                                mapping: 0,
                                repeats: action.repeatsWithScrollMovement,
                                at: time * 1_200_000
                            ))
                        }
                        XCTAssertEqual(counts, [1, 0, 0, 0, 1, 0, 1])
                    }
                }
            }
        }
    }

    func testEveryBuiltInActionExceptScrollOutputUsesThrottlePolicy() {
        typealias Action = Scheme.Buttons.Mapping.Action
        let scrollActions: Set<Action.Arg0> = [
            .mouseWheelScrollUp, .mouseWheelScrollDown, .mouseWheelScrollLeft, .mouseWheelScrollRight
        ]
        for action in Action.Arg0.allCases {
            XCTAssertEqual(Action.arg0(action).repeatsWithScrollMovement, scrollActions.contains(action))
        }
        XCTAssertFalse(Action.arg1(.run("echo example")).repeatsWithScrollMovement)
        for action: Action in [
            .arg1(.mouseWheelScrollUp(.line(3))), .arg1(.mouseWheelScrollDown(.line(3))),
            .arg1(.mouseWheelScrollLeft(.pixel(10))), .arg1(.mouseWheelScrollRight(.pixel(10)))
        ] {
            XCTAssertTrue(action.repeatsWithScrollMovement)
        }
    }

    func testOnlyScrollOutputUsesDistanceInsteadOfThrottle() {
        typealias Action = Scheme.Buttons.Mapping.Action
        XCTAssertFalse(Action.arg1(.keyPress([])).repeatsWithScrollMovement)
        XCTAssertFalse(Action.arg0(.missionControl).repeatsWithScrollMovement)
        XCTAssertFalse(Action.arg0(.missionControlSpaceLeft).repeatsWithScrollMovement)
        XCTAssertFalse(Action.arg0(.mediaMute).repeatsWithScrollMovement)
        XCTAssertFalse(Action.arg0(.mediaVolumeUp).repeatsWithScrollMovement)
        XCTAssertFalse(Action.arg0(.displayBrightnessDown).repeatsWithScrollMovement)
        XCTAssertTrue(Action.arg0(.mouseWheelScrollUp).repeatsWithScrollMovement)
    }
}
