// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
@testable import LinearMouse
import XCTest

final class EventDeviceSnapshotTests: XCTestCase {
    private final class TestDevice {
        let senderID: UInt64
        let onDeinit: () -> Void

        init(senderID: UInt64, onDeinit: @escaping () -> Void = {}) {
            self.senderID = senderID
            self.onDeinit = onDeinit
        }

        deinit {
            onDeinit()
        }
    }

    func testMatchingSenderTakesPrecedenceOverLastActiveDevice() {
        let snapshot = EventDeviceSnapshot<TestDevice>()
        let matching = TestDevice(senderID: 7)
        let fallback = TestDevice(senderID: 8)
        snapshot.replaceDevices([7: matching, 8: fallback])
        snapshot.setLastActiveDevice(fallback)

        XCTAssertIdentical(snapshot.device(for: 7), matching)
        XCTAssertIdentical(snapshot.device(for: 8), fallback)
        XCTAssertIdentical(snapshot.device(for: 9), fallback)
        XCTAssertIdentical(snapshot.device(for: nil), fallback)
    }

    func testUnknownSenderWithoutActiveDeviceReturnsNil() {
        let snapshot = EventDeviceSnapshot<TestDevice>()
        snapshot.replaceDevices([7: TestDevice(senderID: 7)])

        XCTAssertNil(snapshot.device(for: 8))
        XCTAssertNil(snapshot.device(for: nil))
    }

    func testReplacementRemovesOldSendersAndReplacesReusedSender() {
        let snapshot = EventDeviceSnapshot<TestDevice>()
        let previous = TestDevice(senderID: 7)
        let replacement = TestDevice(senderID: 7)
        snapshot.replaceDevices([7: previous, 8: TestDevice(senderID: 8)])
        snapshot.replaceDevices([7: replacement])

        XCTAssertIdentical(snapshot.device(for: 7), replacement)
        XCTAssertNil(snapshot.device(for: 8))

        snapshot.replaceDevices([:])

        XCTAssertNil(snapshot.device(for: 7))
    }

    func testClearingLastActiveDeviceClearsFallback() {
        let snapshot = EventDeviceSnapshot<TestDevice>()
        let device = TestDevice(senderID: 7)
        snapshot.setLastActiveDevice(device)
        snapshot.setLastActiveDevice(nil)

        XCTAssertNil(snapshot.device(for: nil))
        XCTAssertNil(snapshot.device(for: 7))
    }

    func testFallbackDoesNotKeepRemovedDeviceAlive() {
        let snapshot = EventDeviceSnapshot<TestDevice>()
        snapshot.replaceDevices([7: TestDevice(senderID: 7)])
        weak var weakDevice = snapshot.device(for: 7)
        snapshot.setLastActiveDevice(snapshot.device(for: 7))

        XCTAssertNotNil(weakDevice)
        snapshot.replaceDevices([:])

        XCTAssertNil(weakDevice)
        XCTAssertNil(snapshot.device(for: nil))
    }

    func testLookupKeepsDeviceAliveUntilReaderReleasesIt() {
        let snapshot = EventDeviceSnapshot<TestDevice>()
        snapshot.replaceDevices([7: TestDevice(senderID: 7)])
        var result = snapshot.device(for: 7)
        weak var weakDevice = result

        snapshot.replaceDevices([:])

        XCTAssertNil(snapshot.device(for: 7))
        XCTAssertNotNil(weakDevice)
        XCTAssertEqual(result?.senderID, 7)

        result = nil

        XCTAssertNil(weakDevice)
    }

    func testRetiredDeviceCanReenterSnapshotDuringDeinit() {
        let snapshot = EventDeviceSnapshot<TestDevice>()
        let reentered = expectation(description: "Retired device reenters the snapshot")
        let completed = expectation(description: "Replacement and reentrant device teardown complete")
        snapshot.replaceDevices([
            7: TestDevice(senderID: 7) {
                snapshot.setLastActiveDevice(nil)
                XCTAssertNil(snapshot.device(for: 7))
                reentered.fulfill()
            }
        ])

        DispatchQueue.global().async {
            snapshot.replaceDevices([:])
            completed.fulfill()
        }

        wait(for: [reentered, completed], timeout: 2)
    }

    func testConcurrentLookupWhileDevicesAndFallbackChange() {
        let snapshot = EventDeviceSnapshot<TestDevice>()
        let stableDevice = TestDevice(senderID: 9)
        snapshot.replaceDevices([9: stableDevice])
        let failuresLock = NSLock()
        var wrongSenderCount = 0

        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for iteration in 0 ..< 2000 {
                switch worker {
                case 0:
                    snapshot.replaceDevices([
                        7: TestDevice(senderID: 7),
                        8: TestDevice(senderID: 8),
                        9: stableDevice
                    ])
                    snapshot.replaceDevices([9: stableDevice])

                case 1:
                    let fallback = TestDevice(senderID: .max)
                    snapshot.setLastActiveDevice(fallback)
                    withExtendedLifetime(fallback) {
                        _ = snapshot.device(for: nil)
                    }
                    snapshot.setLastActiveDevice(nil)

                default:
                    // This sender remains present through every replacement,
                    // ensuring real retained lookups even when transient
                    // senders disappear before a reader reaches them.
                    if snapshot.device(for: 9) !== stableDevice {
                        failuresLock.withLock {
                            wrongSenderCount += 1
                        }
                    }
                    let senderID: UInt64 = iteration.isMultiple(of: 2) ? 7 : 8
                    if let device = snapshot.device(for: senderID),
                       device.senderID != senderID,
                       device.senderID != .max {
                        failuresLock.withLock {
                            wrongSenderCount += 1
                        }
                    }
                }
            }
        }

        XCTAssertEqual(wrongSenderCount, 0)
    }
}
