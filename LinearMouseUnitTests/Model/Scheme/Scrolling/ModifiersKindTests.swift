// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ModifiersKindTests: XCTestCase {
    func testActionKindMapsPreventDefaultToNoAction() {
        XCTAssertEqual(Scheme.Scrolling.Modifiers.Action.preventDefault.kind, .noAction)
    }

    func testInitFromDefaultActionKindCreatesAutoAction() {
        XCTAssertEqual(Scheme.Scrolling.Modifiers.Action(kind: .defaultAction), .auto)
    }

    func testActionKindMapsPinchZoomReversed() {
        XCTAssertEqual(Scheme.Scrolling.Modifiers.Action.pinchZoomReversed.kind, .pinchZoomReversed)
    }

    func testInitFromPinchZoomReversedKindCreatesPinchZoomReversedAction() {
        XCTAssertEqual(Scheme.Scrolling.Modifiers.Action(kind: .pinchZoomReversed), .pinchZoomReversed)
    }

    func testPinchZoomReversedCodable() throws {
        typealias Action = Scheme.Scrolling.Modifiers.Action

        let decoder = JSONDecoder()
        let action = try decoder.decode(
            Action.self,
            from: Data(#"{"type":"pinchZoomReversed"}"#.utf8)
        )

        XCTAssertEqual(action, .pinchZoomReversed)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        XCTAssertEqual(
            try String(data: encoder.encode(action), encoding: .utf8),
            #"{"type":"pinchZoomReversed"}"#
        )
    }
}
