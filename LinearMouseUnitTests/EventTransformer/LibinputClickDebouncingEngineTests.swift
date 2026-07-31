// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class LibinputClickDebouncingEngineTests: XCTestCase {
    func testFirstPressIsImmediateAndQuickReleaseIsDelayed() {
        var engine = LibinputClickDebouncingEngine()

        XCTAssertEqual(engine.handle(.press), [.setBounceTimer, .emit(.pressed)])
        XCTAssertEqual(engine.state, .isDownWaiting)
        XCTAssertEqual(engine.handle(.release), [.setBounceTimer])
        XCTAssertEqual(engine.state, .isUpDelaying)
        XCTAssertEqual(engine.handle(.bounceTimeout), [.emit(.released)])
        XCTAssertEqual(engine.state, .isUp)
    }

    func testReleaseAfterHeldPressIsImmediate() {
        var engine = LibinputClickDebouncingEngine()

        _ = engine.handle(.press)
        XCTAssertEqual(engine.handle(.bounceTimeout), [])
        XCTAssertEqual(engine.state, .isDown)
        XCTAssertEqual(
            engine.handle(.release),
            [.setBounceTimer, .setSpuriousTimer, .emit(.released)]
        )
        XCTAssertEqual(engine.state, .isUpDetectingSpurious)
    }

    func testPressReleasePressBounceLeavesButtonLogicallyDown() {
        var engine = LibinputClickDebouncingEngine()

        _ = engine.handle(.press)
        XCTAssertEqual(engine.handle(.release), [.setBounceTimer])
        XCTAssertEqual(engine.handle(.press), [.setBounceTimer])
        XCTAssertEqual(engine.handle(.bounceTimeout), [])
        XCTAssertEqual(engine.state, .isDown)

        XCTAssertEqual(
            engine.handle(.release),
            [.setBounceTimer, .setSpuriousTimer, .emit(.released)]
        )
    }

    func testReleasePressReleaseBounceLeavesButtonLogicallyUp() {
        var engine = LibinputClickDebouncingEngine()

        _ = engine.handle(.press)
        _ = engine.handle(.bounceTimeout)
        _ = engine.handle(.release)
        XCTAssertEqual(
            engine.handle(.press),
            [.setBounceTimer, .setSpuriousTimer]
        )
        XCTAssertEqual(
            engine.handle(.release),
            [.setBounceTimer, .setSpuriousTimer]
        )
        XCTAssertEqual(engine.handle(.bounceTimeout), [])
        XCTAssertEqual(engine.state, .isUp)
    }

    func testSpuriousContactLossEnablesShortReleaseDebouncing() {
        var engine = LibinputClickDebouncingEngine()

        _ = engine.handle(.press)
        _ = engine.handle(.bounceTimeout)
        _ = engine.handle(.release)
        _ = engine.handle(.press)

        XCTAssertEqual(
            engine.handle(.spuriousTimeout),
            [.cancelBounceTimer, .spuriousDebouncingEnabled, .emit(.pressed)]
        )
        XCTAssertTrue(engine.spuriousDebouncingEnabled)
        XCTAssertEqual(engine.state, .isDown)

        XCTAssertEqual(
            engine.handle(.release),
            [.setBounceTimer, .setSpuriousTimer]
        )
        XCTAssertEqual(
            engine.handle(.press),
            [.cancelBounceTimer, .cancelSpuriousTimer]
        )
        XCTAssertEqual(engine.state, .isDown)
    }

    func testFinalReleaseIsEmittedInSpuriousMode() {
        var engine = engineWithSpuriousDebouncingEnabled()

        XCTAssertEqual(
            engine.handle(.release),
            [.setBounceTimer, .setSpuriousTimer]
        )
        XCTAssertEqual(engine.handle(.spuriousTimeout), [.emit(.released)])
        XCTAssertEqual(engine.state, .isUpWaiting)
        XCTAssertEqual(engine.handle(.bounceTimeout), [])
        XCTAssertEqual(engine.state, .isUp)
    }

    func testOtherButtonFlushesDelayedRelease() {
        var engine = LibinputClickDebouncingEngine()

        _ = engine.handle(.press)
        _ = engine.handle(.release)

        XCTAssertEqual(
            engine.handle(.otherButton),
            [.cancelBounceTimer, .cancelSpuriousTimer, .emit(.released)]
        )
        XCTAssertEqual(engine.state, .isUp)
    }

    func testOtherButtonFlushesDelayedPressWithoutEnablingSpuriousMode() {
        var engine = LibinputClickDebouncingEngine()

        _ = engine.handle(.press)
        _ = engine.handle(.bounceTimeout)
        _ = engine.handle(.release)
        _ = engine.handle(.press)

        XCTAssertEqual(
            engine.handle(.otherButton),
            [.cancelBounceTimer, .cancelSpuriousTimer, .emit(.pressed)]
        )
        XCTAssertFalse(engine.spuriousDebouncingEnabled)
        XCTAssertEqual(engine.state, .isDown)
    }

    func testUnmatchedReleaseIsForwardedToAvoidStuckButton() {
        var engine = LibinputClickDebouncingEngine()

        XCTAssertEqual(engine.handle(.release), [.emit(.released)])
        XCTAssertEqual(engine.state, .isUp)
    }

    private func engineWithSpuriousDebouncingEnabled() -> LibinputClickDebouncingEngine {
        var engine = LibinputClickDebouncingEngine()
        _ = engine.handle(.press)
        _ = engine.handle(.bounceTimeout)
        _ = engine.handle(.release)
        _ = engine.handle(.press)
        _ = engine.handle(.spuriousTimeout)
        return engine
    }
}
