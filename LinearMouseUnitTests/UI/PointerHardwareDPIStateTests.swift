// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class PointerHardwareDPIStateTests: XCTestCase {
    func testSuccessfulApplyDisplaysAppliedDPI() {
        let result = Device.HardwareDPIApplyResult(
            targetDPI: 8000,
            info: .init(
                supportsAdjustableDPI: true,
                currentDPI: 1000,
                dpiRange: 200 ... 8000
            )
        )

        XCTAssertEqual(PointerSettingsState.displayedHardwareDPI(after: result), 8000)
    }

    func testFailedApplyRevertsToLastKnownDPI() {
        let result = Device.HardwareDPIApplyResult(
            targetDPI: nil,
            info: .init(
                supportsAdjustableDPI: true,
                currentDPI: 1000,
                dpiRange: 200 ... 8000
            )
        )

        XCTAssertEqual(PointerSettingsState.displayedHardwareDPI(after: result), 1000)
    }

    func testFailedApplyWithoutKnownDPIHasNoDisplayValue() {
        let result = Device.HardwareDPIApplyResult(
            targetDPI: nil,
            info: .init(
                supportsAdjustableDPI: true,
                currentDPI: nil,
                dpiRange: 200 ... 8000
            )
        )

        XCTAssertNil(PointerSettingsState.displayedHardwareDPI(after: result))
    }
}
