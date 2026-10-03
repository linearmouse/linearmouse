// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
@testable import LinearMouse
import XCTest

final class HoverWindowQueryTests: XCTestCase {
    /// Run with a fresh test host to exercise the first AXChildren query while
    /// the settings window is still initializing. Do not warm up AX on main.
    func testOwnSettingsWindowCanBeQueriedDuringOpening() {
        let completed = expectation(description: "Query settings window during startup")
        DispatchQueue.main.async {
            SettingsWindowController.shared.bringToFront()
            guard let window = SettingsWindowController.shared.window,
                  let screen = NSScreen.screens.first else {
                XCTFail("Missing settings window or screen")
                completed.fulfill()
                return
            }
            let target = HoverWindowQuery.Focus(pid: getpid(), windowID: CGWindowID(window.windowNumber))
            let point = CGPoint(x: window.frame.midX, y: screen.frame.maxY - window.frame.midY)
            DispatchQueue(label: "test.hover-focus.opening").async {
                let query = HoverWindowQuery()
                var eligibleQueries = 0
                for _ in 0 ..< 200 {
                    if query.canFocus(target, at: point) {
                        eligibleQueries += 1
                    }
                    Thread.sleep(forTimeInterval: 0.01)
                }
                // The initial accessory-to-regular activation transition may
                // temporarily make the window ineligible.
                XCTAssertGreaterThan(eligibleQueries, 0)
                DispatchQueue.main.async {
                    window.close()
                    completed.fulfill()
                }
            }
        }
        wait(for: [completed], timeout: 15)
    }

    func testOwnApplicationQueryRunsOnMainFromWorker() {
        let completed = expectation(description: "Local AX query completes")
        DispatchQueue(label: "test.hover-focus").async {
            let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            let result = HoverWindowQuery.performAXQuery(on: application) {
                XCTAssertTrue(Thread.isMainThread)
                return 42
            }
            XCTAssertEqual(result, 42)
            XCTAssertFalse(Thread.isMainThread)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
    }

    func testOwnApplicationQueryOnMainDoesNotRedispatch() {
        let completed = expectation(description: "Main-thread AX query completes without deadlocking")
        DispatchQueue.main.async {
            let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            HoverWindowQuery.performAXQuery(on: application) {
                XCTAssertTrue(Thread.isMainThread)
            }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
    }

    func testRemoteApplicationQueryStaysOnWorker() {
        let completed = expectation(description: "Remote AX query stays off main")
        let queue = DispatchQueue(label: "test.hover-focus.remote")
        queue.async {
            let application = AXUIElementCreateApplication(getppid())
            HoverWindowQuery.performAXQuery(on: application) {
                dispatchPrecondition(condition: .onQueue(queue))
                XCTAssertFalse(Thread.isMainThread)
            }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
    }

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
