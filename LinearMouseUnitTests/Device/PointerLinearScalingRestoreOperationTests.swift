// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class PointerLinearScalingRestoreOperationTests: XCTestCase {
    func testRestoresExactEnabledAndDisabledBaselines() {
        var writes = [Int]()

        PointerLinearScalingRestoreOperation.perform(baseline: 1) {
            writes.append($0)
        }
        PointerLinearScalingRestoreOperation.perform(baseline: 0) {
            writes.append($0)
        }

        XCTAssertEqual(writes, [1, 0])
    }

    func testMissingBaselineDoesNotWrite() {
        var writes = [Int]()

        PointerLinearScalingRestoreOperation.perform(baseline: nil) {
            writes.append($0)
        }

        XCTAssertTrue(writes.isEmpty)
    }
}
