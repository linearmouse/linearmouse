// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
@testable import PointerKit
import XCTest

final class PointerDeviceSynchronousRequestTests: XCTestCase {
    func testCancellationAfterGateAcquisitionReleasesPermit() {
        // A zero-count gate models a first request holding the permit. The
        // second request is cancelled immediately after its wait succeeds.
        let gate = DispatchSemaphore(value: 0)
        let beganWaiting = expectation(description: "second request began waiting")
        let finished = expectation(description: "second request finished")
        let lock = NSLock()
        var shouldContinueCallCount = 0
        var operationWasCalled = false

        DispatchQueue.global().async {
            let response = withSynchronousReportRequestGate(
                gate,
                until: {
                    lock.withLock {
                        shouldContinueCallCount += 1
                        if shouldContinueCallCount == 1 {
                            beganWaiting.fulfill()
                            return true
                        }
                        return false
                    }
                },
                perform: {
                    lock.withLock {
                        operationWasCalled = true
                    }
                    return Data([0x01])
                }
            )

            XCTAssertNil(response)
            finished.fulfill()
        }

        wait(for: [beganWaiting], timeout: 1)
        gate.signal()
        wait(for: [finished], timeout: 1)

        XCTAssertFalse(lock.withLock { operationWasCalled })
        XCTAssertEqual(
            withSynchronousReportRequestGate(gate, until: { true }) { Data([0x02]) },
            Data([0x02])
        )
    }
}
