// MIT License
// Copyright (c) 2021-2025 LinearMouse

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
            let nsEvent = NSEvent(cgEvent: cgEvent)!
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
}
