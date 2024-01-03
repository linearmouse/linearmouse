// MIT License
// Copyright (c) 2021-2024 LinearMouse

import AppKit
import os.log

class GlobalEventTapWatchdog {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "GlobalEventTapWatchdog")

    init() {}

    deinit {
        stop()
    }

    var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self = self else {
                return
            }

            self.testAccessibilityPermission()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func testAccessibilityPermission() {
        do {
            try EventTap.observe([.scrollWheel]) { _, event in
                event
            }.removeLifetime()
        } catch {
            stop()
            Application.restart()
        }
    }
}
