// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Repeats a block across the window in which macOS restores its own HID properties after a wake.
///
/// Waking is not a single moment. `NSWorkspace.didWakeNotification` fires before the HID stack has
/// finished restoring device properties, so anything written while handling it is overwritten
/// shortly afterwards. Repeating the write over the settle window keeps the configured values in
/// place instead of leaving them to be restored by an unrelated event.
///
/// The cadence is deliberately flat rather than backed off: the reset can land at any point in the
/// window, and the interval is the worst case for how long the pointer stays wrong before it is
/// corrected.
///
/// Each `restart` cancels the pending series, so overlapping wakes do not stack up.
final class WakeReapplyScheduler {
    /// How long to wait between re-applies.
    static let defaultInterval: TimeInterval = 1

    /// How many times to re-apply. With the default interval this covers the 30 seconds after a
    /// wake, which is enough for a receiver behind a dock or a device reconnecting over Bluetooth.
    static let defaultAttempts = 30

    typealias Schedule = (TimeInterval, @escaping () -> Void) -> DispatchWorkItem

    private let delays: [TimeInterval]
    private let schedule: Schedule
    private var pending: [DispatchWorkItem] = []

    init(
        interval: TimeInterval = defaultInterval,
        attempts: Int = defaultAttempts,
        schedule: @escaping Schedule = { delay, block in
            let workItem = DispatchWorkItem(block: block)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            return workItem
        }
    ) {
        delays = (1 ... max(attempts, 1)).map { TimeInterval($0) * interval }
        self.schedule = schedule
    }

    deinit {
        pending.forEach { $0.cancel() }
    }

    /// The window this scheduler covers, for logging.
    var duration: TimeInterval {
        delays.last ?? 0
    }

    /// Cancels any pending run and schedules a fresh series of `block` runs.
    func restart(_ block: @escaping () -> Void) {
        cancel()
        pending = delays.map { schedule($0, block) }
    }

    func cancel() {
        pending.forEach { $0.cancel() }
        pending.removeAll()
    }
}
