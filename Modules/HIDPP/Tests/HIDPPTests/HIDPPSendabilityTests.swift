// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP
import XCTest

final class HIDPPSendabilityTests: XCTestCase {
    /// A consumer must be able to include these public values in its own
    /// Sendable snapshot without depending on HIDPP's implementation details.
    private struct FeatureSnapshot: Sendable {
        let featureID: HIDPPFeatureID
        let response: HIDPPResponse
        let capabilities: HiResWheel.Capabilities
        let result: HiResWheel.ApplyResult
    }

    func testProtocolValuesCanBeSharedWithAnotherQueue() {
        let snapshot = FeatureSnapshot(
            featureID: .hiresWheel,
            response: HIDPPResponse(payload: [0x02, 0x05]),
            capabilities: HiResWheel.Capabilities(multiplier: 2, flags: 5),
            result: HiResWheel.ApplyResult(previousEnabled: false, appliedEnabled: true)
        )
        let completed = expectation(description: "Protocol values consumed on another queue")

        DispatchQueue.global().async {
            XCTAssertEqual(snapshot.featureID.bytes, [0x21, 0x21])
            XCTAssertEqual(snapshot.response.payload, [0x02, 0x05])
            XCTAssertEqual(snapshot.capabilities.multiplier, 2)
            XCTAssertEqual(snapshot.capabilities.flags, 5)
            XCTAssertFalse(snapshot.result.previousEnabled)
            XCTAssertTrue(snapshot.result.appliedEnabled)
            completed.fulfill()
        }

        // The producer keeps using the same snapshot after dispatching it.
        XCTAssertEqual(snapshot.featureID, HiResWheel.featureID)
        XCTAssertEqual(snapshot.response.payload, [0x02, 0x05])
        wait(for: [completed], timeout: 2)
    }
}
