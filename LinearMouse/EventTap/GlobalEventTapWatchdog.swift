// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import os.log

class GlobalEventTapWatchdog {
    typealias Probe = (@escaping (Bool) -> Void) -> Void

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "GlobalEventTapWatchdog")
    private static let queue = DispatchQueue(label: "app.linearmouse.event-tap-watchdog", qos: .utility)
    private let probe: Probe
    private let onFailure: () -> Void
    private var timer: Timer?
    private var checking = false
    private var watchID = 0

    init(
        probe: @escaping Probe = GlobalEventTapWatchdog.probeEventAccess,
        onFailure: @escaping () -> Void = Application.restart
    ) {
        self.probe = probe
        self.onFailure = onFailure
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        watchID += 1
        timer?.invalidate()
        timer = nil
    }

    func check() {
        guard timer != nil, !checking else {
            return
        }
        checking = true
        let expectedWatchID = watchID
        probe { [weak self] available in
            guard let self else {
                return
            }
            checking = false
            guard watchID == expectedWatchID, timer != nil, !available else {
                return
            }
            stop()
            os_log("Event access probe failed; restarting LinearMouse", log: Self.log, type: .error)
            onFailure()
        }
    }

    /// Preserve the original watchdog's real event-tap probe: permission APIs
    /// can report a cached grant after access has been revoked. The temporary
    /// tap is never attached to a run loop and is invalidated immediately.
    private static func probeEventAccess(completion: @escaping (Bool) -> Void) {
        queue.async {
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1) << CGEventType.scrollWheel.rawValue,
                callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
                userInfo: nil
            )
            if let tap {
                CFMachPortInvalidate(tap)
            }
            DispatchQueue.main.async { completion(tap != nil) }
        }
    }
}
