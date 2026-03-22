// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class MappingActionKindTests: XCTestCase {
    func testMappingActionKindReadsScrollKind() {
        let action = Scheme.Buttons.Mapping.Action.arg1(.mouseWheelScrollRight(.pixel(20)))

        XCTAssertEqual(action.kind, .mouseWheelScrollRight)
    }

    func testInitFromRunKindCreatesEmptyRunCommand() {
        XCTAssertEqual(Scheme.Buttons.Mapping.Action(kind: .run), .arg1(.run("")))
    }
}
