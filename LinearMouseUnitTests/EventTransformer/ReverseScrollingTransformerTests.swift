// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ReverseScrollingTransformerTests: XCTestCase {
    func testReverseScrollingVertically() throws {
        let transformer = ReverseScrollingTransformer(vertically: true)
        var event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 2,
            wheel3: 0
        ))
        event = try XCTUnwrap(transformer.transform(event, in: EventTransformerContext(device: nil)))
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, 2)
        XCTAssertEqual(view.deltaY, -1)
    }

    func testReverseScrollingHorizontally() throws {
        let transformer = ReverseScrollingTransformer(horizontally: true)
        var event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 2,
            wheel3: 0
        ))
        event = try XCTUnwrap(transformer.transform(event, in: EventTransformerContext(device: nil)))
        let view = ScrollWheelEventView(event)
        XCTAssertEqual(view.deltaX, -2)
        XCTAssertEqual(view.deltaY, 1)
    }

    func testMouseReversalIsUndoneWhereTheSchemeDoesNotReverse() throws {
        let transformer = ReverseScrollingTransformer { _ in true }
        let view = try transformedView(transformer)
        XCTAssertEqual(view.deltaX, 2)
        XCTAssertEqual(view.deltaY, -1)
    }

    func testMouseReversalReplacesSoftwareReversal() throws {
        let transformer = ReverseScrollingTransformer(vertically: true, horizontally: true) { _ in true }
        let view = try transformedView(transformer)
        XCTAssertEqual(view.deltaX, -2)
        XCTAssertEqual(view.deltaY, 1)
    }

    func testDeviceWithoutMouseReversalIsNotLogitechReversed() {
        XCTAssertFalse(ReverseScrollingTransformer.logitechMouseReversesVertically(
            in: EventTransformerContext(device: nil)
        ))
    }

    private func transformedView(_ transformer: ReverseScrollingTransformer) throws -> ScrollWheelEventView {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 2,
            wheel3: 0
        ))
        let transformed = try XCTUnwrap(transformer.transform(event, in: EventTransformerContext(device: nil)))
        return ScrollWheelEventView(transformed)
    }
}
