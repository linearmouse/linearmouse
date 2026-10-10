// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class GlobalEventTapWatchdogTests: XCTestCase {
    func testFailedRealProbeRestartsOnlyOnce() {
        var failures = 0
        let watchdog = GlobalEventTapWatchdog(probe: { $0(false) }, onFailure: { failures += 1 })
        watchdog.start()
        watchdog.check()
        watchdog.check()
        XCTAssertEqual(failures, 1)
    }

    func testHealthyProbeKeepsWatchdogRunning() {
        var probes = 0
        let watchdog = GlobalEventTapWatchdog(probe: { completion in
            probes += 1
            completion(true)
        }, onFailure: { XCTFail("Healthy tap must not restart the app") })
        watchdog.start()
        watchdog.check()
        watchdog.check()
        XCTAssertEqual(probes, 2)
        watchdog.stop()
    }

    func testSlowProbeDoesNotOverlapAndStoppedResultsAreIgnored() {
        var completions: [(Bool) -> Void] = []
        let watchdog = GlobalEventTapWatchdog(probe: { completions.append($0) }, onFailure: { XCTFail("Stale probe") })
        watchdog.start()
        watchdog.check()
        watchdog.check()
        XCTAssertEqual(completions.count, 1)
        watchdog.stop()
        completions[0](false)
        watchdog.check()
        XCTAssertEqual(completions.count, 1)
    }

    func testOldFailureCannotRestartNewWatchdogSession() {
        var completions: [(Bool) -> Void] = []
        var failures = 0
        let watchdog = GlobalEventTapWatchdog(probe: { completions.append($0) }, onFailure: { failures += 1 })
        watchdog.start()
        watchdog.check()
        watchdog.stop()
        watchdog.start()
        completions[0](false)
        XCTAssertEqual(failures, 0)
        watchdog.check()
        completions[1](false)
        XCTAssertEqual(failures, 1)
    }
}
