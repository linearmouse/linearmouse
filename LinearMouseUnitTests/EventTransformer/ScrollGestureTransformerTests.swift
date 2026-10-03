// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ScrollGestureTransformerTests: XCTestCase {
    func testOwnedMomentumSurvivesRouteWithoutMappings() throws {
        defer { ConfigurationState.shared.configuration = .init() }
        var scheme = Scheme(if: [.init(display: "scroll-test-A")])
        scheme.buttons.mappings = [.init(trigger: .init(input: .wheel(.up)), action: .arg0(.none))]
        ConfigurationState.shared.configuration = .init(schemes: [scheme])
        let manager = EventTransformerManager(warpPointer: { _ in }, postEvent: { _, _ in })
        let event = try scrollEvent()
        ScrollWheelEventView(event).scrollPhase = .began
        let first = manager.get(withDevice: nil, withPid: nil, withDisplay: "scroll-test-A")
        XCTAssertNil(first.transform(event, in: .init(device: nil)))
        let next = manager.get(withDevice: nil, withPid: nil, withDisplay: "scroll-test-B")
        let view = ScrollWheelEventView(event)
        view.scrollPhase = nil
        view.momentumPhase = .begin
        XCTAssertNil(next.transform(event, in: .init(device: nil)))
        view.momentumPhase = .end
        XCTAssertNil(next.transform(event, in: .init(device: nil)))
        view.momentumPhase = .none
        view.scrollPhase = .began
        XCTAssertNotNil(next.transform(event, in: .init(device: nil)))
        view.scrollPhase = nil
        view.momentumPhase = .begin
        XCTAssertNotNil(next.transform(event, in: .init(device: nil)))
    }

    func testNewGestureOnUnmappedRouteReleasesPreviousOwnership() throws {
        defer { ConfigurationState.shared.configuration = .init() }
        var scheme = Scheme(if: [.init(display: "scroll-test-A")])
        scheme.buttons.mappings = [.init(trigger: .init(input: .wheel(.up)), action: .arg0(.none))]
        ConfigurationState.shared.configuration = .init(schemes: [scheme])
        let manager = EventTransformerManager(warpPointer: { _ in }, postEvent: { _, _ in })
        let first = manager.get(withDevice: nil, withPid: nil, withDisplay: "scroll-test-A")
        let event = try scrollEvent()
        let view = ScrollWheelEventView(event)
        view.scrollPhase = .began
        XCTAssertNil(first.transform(event, in: .init(device: nil)))
        let next = manager.get(withDevice: nil, withPid: nil, withDisplay: "scroll-test-B")
        XCTAssertNotNil(next.transform(event, in: .init(device: nil)))
        view.scrollPhase = nil
        view.momentumPhase = .begin
        XCTAssertNotNil(first.transform(event, in: .init(device: nil)))
    }

    func testSyntheticGestureDoesNotReleasePhysicalOwnership() throws {
        let ownership = ScrollGestureOwnership()
        let transformer = ScrollGestureTransformer(ownership: ownership)
        ownership.claim()
        let event = try scrollEvent()
        event.isLinearMouseSyntheticEvent = true
        ScrollWheelEventView(event).scrollPhase = .began
        XCTAssertNotNil(transformer.transform(event, in: .init(device: nil)))
        XCTAssertTrue(ownership.isOwned)
        let physical = try scrollEvent()
        ScrollWheelEventView(physical).scrollPhase = .began
        XCTAssertNotNil(transformer.transform(physical, in: .init(device: nil)))
        XCTAssertFalse(ownership.isOwned)
    }

    private func scrollEvent() throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 8, wheel2: 0, wheel3: 0
        ))
        event.flags = []
        ScrollWheelEventView(event).momentumPhase = .none
        ScrollWheelEventView(event).scrollPhase = nil
        return event
    }
}
