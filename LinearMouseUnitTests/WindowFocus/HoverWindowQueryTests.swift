// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
@testable import LinearMouse
import XCTest

final class HoverWindowQueryTests: XCTestCase {
    private func window(_ id: UInt32, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: pid_t(id + 10),
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: CGRect(x: -100, y: -100, width: 200, height: 200)
                .dictionaryRepresentation
        ]
    }

    func testWindowServerTargetWinsOverBoundingRectanglesOfClickThroughSurfaces() {
        let target = HoverWindowQuery.Focus(pid: 12, windowID: 2)
        for layer in [0, 3, 20, 24, 101] {
            XCTAssertEqual(
                HoverWindowQuery.validateWindow(target, in: [window(1, layer: layer), window(2)], at: .zero),
                target
            )
        }
    }

    func testMissingWindowOrMismatchedOwnerIsRejected() {
        for target in [HoverWindowQuery.Focus(pid: 13, windowID: 3), .init(pid: 99, windowID: 2)] {
            XCTAssertNil(HoverWindowQuery.validateWindow(target, in: [window(1), window(2)], at: .zero))
        }
    }

    func testHitOnActualFloatingWindowDoesNotFallThroughToDocument() {
        let target = HoverWindowQuery.Focus(pid: 11, windowID: 1)
        for layer in [3, 20, 24, 101] {
            XCTAssertNil(HoverWindowQuery.validateWindow(target, in: [window(1, layer: layer), window(2)], at: .zero))
        }
    }

    func testInvisibleTargetAndOutsideBoundsAreRejected() {
        let target = HoverWindowQuery.Focus(pid: 11, windowID: 1)
        XCTAssertNil(HoverWindowQuery.validateWindow(target, in: [window(1, alpha: 0)], at: .zero))
        XCTAssertNil(HoverWindowQuery.validateWindow(target, in: [window(1)], at: .init(x: 200, y: 0)))
        XCTAssertEqual(HoverWindowQuery.validateWindow(target, in: [window(1)], at: .init(x: -50, y: -50)), target)
    }

    func testExactWindowIDIsRequiredWithinApplication() {
        XCTAssertEqual(HoverWindowQuery.matchingWindow(in: [1, 2, 3], targetID: 2) { UInt32($0) }, 2)
        XCTAssertNil(HoverWindowQuery.matchingWindow(in: [1, 3], targetID: 2) { UInt32($0) })
        XCTAssertNil(HoverWindowQuery.matchingWindow(in: [1, 2], targetID: 2) { _ in nil })
    }
}
