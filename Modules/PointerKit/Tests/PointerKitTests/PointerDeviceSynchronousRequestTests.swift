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
                acquirePermit: {
                    gate.wait(timeout: .now() + 0.01) == .success
                },
                releasePermit: {
                    gate.signal()
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
            withSynchronousReportRequestGate(
                until: { true },
                acquirePermit: { gate.wait(timeout: .now()) == .success },
                releasePermit: { gate.signal() }
            ) { Data([0x02]) },
            Data([0x02])
        )
    }

    func testOwnerWaitHookLetsGateHolderReleaseBeforeRetry() {
        let gate = DispatchSemaphore(value: 0)
        let holderReady = expectation(description: "background request holds gate")
        let ownerWaitHookRan = expectation(description: "owner wait hook ran")
        let releaseHolder = DispatchSemaphore(value: 0)
        let hookLock = NSLock()
        var didRunOwnerWaitHook = false

        DispatchQueue.global().async {
            holderReady.fulfill()
            _ = releaseHolder.wait(timeout: .now() + 1)
            gate.signal()
        }

        wait(for: [holderReady], timeout: 1)
        let response = withSynchronousReportRequestGate(
            until: { true },
            acquirePermit: {
                if gate.wait(timeout: .now()) == .success {
                    return true
                }

                let shouldRunHook = hookLock.withLock { () -> Bool in
                    guard !didRunOwnerWaitHook else {
                        return false
                    }

                    didRunOwnerWaitHook = true
                    return true
                }
                if shouldRunHook {
                    ownerWaitHookRan.fulfill()
                    releaseHolder.signal()
                }
                return false
            },
            releasePermit: { gate.signal() }
        ) {
            Data([0x03])
        }

        XCTAssertEqual(response, Data([0x03]))
        wait(for: [ownerWaitHookRan], timeout: 1)
        XCTAssertEqual(
            withSynchronousReportRequestGate(
                until: { true },
                acquirePermit: { gate.wait(timeout: .now()) == .success },
                releasePermit: { gate.signal() }
            ) { Data([0x04]) },
            Data([0x04])
        )
    }

    func testCancellationAfterCommitDrainsResponseBeforeReleasingGate() {
        let gate = DispatchSemaphore(value: 1)
        var committedResponse: Data?
        var waitCount = 0

        let result = withSynchronousReportRequestGate(
            until: { true },
            acquirePermit: { gate.wait(timeout: .now()) == .success },
            releasePermit: { gate.signal() }
        ) {
            settleCommittedSynchronousReportRequest(
                until: Date().addingTimeInterval(1),
                shouldDeliverResult: { false },
                isTransportValid: { true },
                wait: { _ in
                    waitCount += 1
                    committedResponse = Data([0x05])
                },
                response: { committedResponse }
            )
        }

        XCTAssertNil(result)
        XCTAssertEqual(waitCount, 1)
        XCTAssertEqual(
            withSynchronousReportRequestGate(
                until: { true },
                acquirePermit: { gate.wait(timeout: .now()) == .success },
                releasePermit: { gate.signal() }
            ) { Data([0x06]) },
            Data([0x06])
        )
    }
}
