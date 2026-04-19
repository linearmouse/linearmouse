// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class EventTransformerManagerTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ConfigurationState.shared.configuration = .init()
    }

    func testSyntheticSmoothedEventStillGetsModifierActions() throws {
        let modifiers = Scheme.Scrolling.Modifiers(option: .changeSpeed(scale: 2))
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                scrolling: .init(
                    reverse: .init(vertical: true),
                    acceleration: .init(vertical: 2),
                    smoothed: .init(vertical: .init(enabled: true, preset: .smooth)),
                    modifiers: .init(vertical: modifiers)
                )
            )
        ])

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        ))
        let view = ScrollWheelEventView(event)
        view.continuous = true
        view.deltaYPt = 12
        view.deltaYFixedPt = 12
        event.flags = [.maskAlternate]
        event.isLinearMouseSyntheticEvent = true

        let transformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        let transformedEvent = try XCTUnwrap(transformer.transform(event))
        let transformedView = ScrollWheelEventView(transformedEvent)

        XCTAssertEqual(transformedView.deltaYPt, 24, accuracy: 0.001)
        XCTAssertEqual(transformedView.deltaYFixedPt, 24, accuracy: 0.001)
        XCTAssertEqual(transformedEvent.flags, [])
    }

    func testDisabledSmoothedConfigurationFallsBackToLegacyScrolling() throws {
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(scrolling: .init(
                smoothed: .init(vertical: .init(enabled: true, preset: .smooth))
            )),
            Scheme(scrolling: .init(
                distance: .init(vertical: .line(3)),
                smoothed: .init(vertical: .init(enabled: false))
            ))
        ])

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))

        let transformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        let transformedEvent = try XCTUnwrap(transformer.transform(event))
        let view = ScrollWheelEventView(transformedEvent)

        XCTAssertEqual(view.deltaY, 3)
        XCTAssertEqual(view.scrollPhase, nil)
        XCTAssertEqual(view.momentumPhase, .none)
    }

    func testContinuousTrackpadEventStillGetsReverseScrollingWhenSmoothedExists() throws {
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                scrolling: .init(
                    reverse: .init(vertical: true),
                    smoothed: .init(vertical: .init(enabled: true, preset: .easeInOut))
                )
            )
        ])

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        ))
        let view = ScrollWheelEventView(event)
        view.continuous = true
        view.deltaYPt = 12
        view.deltaYFixedPt = 12
        view.scrollPhase = .began

        let transformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        let transformedEvent = try XCTUnwrap(transformer.transform(event))
        let transformedView = ScrollWheelEventView(transformedEvent)

        XCTAssertEqual(transformedView.deltaYPt, 0, accuracy: 0.001)
        XCTAssertLessThan(transformedView.deltaYFixedPt, 0)
        XCTAssertGreaterThan(transformedView.deltaYFixedPt, -12)
        XCTAssertEqual(transformedView.scrollPhase, .began)
    }

    func testButtonActionTransformerReceivesUniversalBackForwardSetting() throws {
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(
                mappings: [.init(scroll: .left, action: .arg0(.mouseButtonBack))],
                universalBackForward: .both
            ))
        ])

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 1,
            wheel3: 0
        ))

        let transformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        let buttonActionsTransformer = try XCTUnwrap((transformer as? [EventTransformer])?
            .compactMap { $0 as? ButtonActionsTransformer }
            .first)

        XCTAssertEqual(buttonActionsTransformer.universalBackForward, .both)
    }
}
