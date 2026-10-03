// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class SchemeDiffTests: XCTestCase {
    func testMissingPreviousSchemeMarksAllFieldsChanged() {
        let diff = SchemeDiff(previous: nil, current: Scheme())
        XCTAssertTrue(diff.changed(\.pointer.speed))
        XCTAssertTrue(diff.changed(\.scrolling))
        XCTAssertTrue(diff.changed(\.buttons))
    }

    func testUnrelatedSectionsDoNotCausePointerChanges() {
        let previous = Scheme()
        var current = previous
        current.buttons.switchPrimaryButtonAndSecondaryButtons = true
        current.logitech.highResolutionWheel = true
        let diff = SchemeDiff(previous: previous, current: current)
        XCTAssertTrue(diff.changed(\.buttons))
        XCTAssertTrue(diff.changed(\.logitech.highResolutionWheel))
        XCTAssertFalse(diff.changed(\.pointer))
        XCTAssertFalse(diff.changed(\.scrolling))
    }

    func testRawDiffPreservesUnsetAndExplicitFalse() {
        var current = Scheme()
        current.pointer.speed = .unset
        current.pointer.acceleration = .unset
        current.pointer.disableAcceleration = false
        let diff = SchemeDiff(previous: Scheme(), current: current)
        XCTAssertTrue(diff.changed(\.pointer.speed))
        XCTAssertTrue(diff.changed(\.pointer.acceleration))
        XCTAssertTrue(diff.changed(\.pointer.disableAcceleration))
    }
}
