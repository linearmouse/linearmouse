// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
@testable import PointerKit
import XCTest

final class PointerDeviceRunLoopSchedulingTests: XCTestCase {
    func testInputCallbacksUseOneSharedCommonModePolicy() {
        let scheduling = PointerDeviceRunLoopScheduling.inputCallbacks

        XCTAssertTrue(CFEqual(scheduling.mode.rawValue, CFRunLoopMode.commonModes.rawValue))
    }

    func testCommonModeWorkIsDeliveredWhileRunningAModalMode() {
        let runLoop = CFRunLoopGetCurrent()
        let modalMode = CFRunLoopMode(rawValue: "NSModalPanelRunLoopMode" as CFString)
        CFRunLoopAddCommonMode(runLoop, modalMode)

        var delivered = false
        CFRunLoopPerformBlock(
            runLoop,
            PointerDeviceRunLoopScheduling.inputCallbacks.mode.rawValue
        ) {
            delivered = true
        }
        CFRunLoopWakeUp(runLoop)

        _ = CFRunLoopRunInMode(modalMode, 0.1, true)

        XCTAssertTrue(delivered)
    }
}
