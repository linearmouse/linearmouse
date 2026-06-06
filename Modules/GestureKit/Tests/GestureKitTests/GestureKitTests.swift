// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import GestureKit
import XCTest

final class GestureKitTests: XCTestCase {
    func testNavigationSwipeGesture() throws {
        guard let event = GestureEvent(navigationSwipeSource: nil, direction: .swipeLeft) else {
            XCTFail("event should not be nil")
            return
        }

        let cgEvents = event.cgEvents
        XCTAssertEqual(cgEvents.count, 2)

        for (index, cgEvent) in cgEvents.enumerated() {
            let nsEvent = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
            XCTAssertEqual(nsEvent.type, .swipe)
            switch index {
            case 0:
                XCTAssertEqual(nsEvent.phase, .began)
            case 1:
                XCTAssertEqual(nsEvent.phase, .ended)
            default:
                break
            }
        }
    }

    func testScrollGesture() throws {
        guard let event = GestureEvent(
            scrollSource: nil,
            phase: .began,
            deltaX: 4,
            deltaY: -2,
            flags: [.maskShift]
        ) else {
            XCTFail("event should not be nil")
            return
        }

        let cgEvent = try XCTUnwrap(event.cgEvents.first)
        let gestureType = try XCTUnwrap(CGEventType(nsEventType: .gesture))
        XCTAssertEqual(cgEvent.type, gestureType)
        XCTAssertEqual(cgEvent.flags, [.maskShift])
        XCTAssertEqual(cgEvent.getIntegerValueField(.gestureHIDType), Int64(IOHIDEventType.scroll.rawValue))
        XCTAssertEqual(cgEvent.getIntegerValueField(.gesturePhase), Int64(CGSGesturePhase.began.rawValue))
        XCTAssertEqual(cgEvent.getIntegerValueField(.scrollGestureFlagBits), 1)
        XCTAssertEqual(cgEvent.getDoubleValueField(.gestureScrollX), 4)
        XCTAssertEqual(cgEvent.getDoubleValueField(.gestureScrollY), -2)
    }

    func testScrollGestureSeriesBoundary() throws {
        let started = try XCTUnwrap(GestureEvent(scrollSeriesSource: nil, started: true))
        let ended = try XCTUnwrap(GestureEvent(scrollSeriesSource: nil, started: false))

        let startedEvent = try XCTUnwrap(started.cgEvents.first)
        let gestureType = try XCTUnwrap(CGEventType(nsEventType: .gesture))
        XCTAssertEqual(startedEvent.type, gestureType)
        XCTAssertEqual(
            startedEvent.getIntegerValueField(.gestureHIDType),
            Int64(IOHIDEventType.gestureStarted.rawValue)
        )
        XCTAssertEqual(
            startedEvent.getIntegerValueField(.gestureStartEndSeriesType),
            Int64(IOHIDEventType.scroll.rawValue)
        )

        let endedEvent = try XCTUnwrap(ended.cgEvents.first)
        XCTAssertEqual(endedEvent.type, gestureType)
        XCTAssertEqual(
            endedEvent.getIntegerValueField(.gestureHIDType),
            Int64(IOHIDEventType.gestureEnded.rawValue)
        )
        XCTAssertEqual(
            endedEvent.getIntegerValueField(.gestureStartEndSeriesType),
            Int64(IOHIDEventType.scroll.rawValue)
        )
    }
}
