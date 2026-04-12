// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import os.log

/// Manages a dedicated background thread with its own RunLoop for CGEvent processing.
///
/// All event transformer state access (transform, tick, deactivate) must happen on this thread.
/// Use ``perform(_:)`` to dispatch work from other threads, and ``scheduleTimer(interval:repeats:handler:)``
/// to create timers that fire on this thread.
final class EventThread {
    static let shared = EventThread()

    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "EventThread")

    /// The RunLoop of the background thread. Nil when the thread is not running.
    /// Exposed for `EventTap` to attach its `CFMachPort` source.
    private(set) var runLoop: RunLoop?

    /// Called on the event thread just before it stops.
    /// Set by `GlobalEventTap` to wire up cleanup (e.g. cache invalidation) without tight coupling.
    var onWillStop: (() -> Void)?

    private var thread: Thread?
    private let runLoopReady = DispatchSemaphore(value: 0)

    init() {}

    /// Whether the current thread is the event processing thread.
    var isCurrent: Bool {
        Thread.current === thread
    }

    // MARK: - Lifecycle

    func start() {
        guard thread == nil else {
            return
        }

        let thread = Thread { [weak self] in
            guard let self else {
                return
            }
            let rl = RunLoop.current
            // Keep the RunLoop alive even without event sources.
            rl.add(Port(), forMode: .common)
            self.runLoop = rl
            self.runLoopReady.signal()
            CFRunLoopRun()
        }
        thread.name = "com.linearmouse.event-thread"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread

        runLoopReady.wait()
    }

    /// Stop the event thread synchronously.
    ///
    /// Fires `onWillStop` on the event thread, waits for the RunLoop to exit,
    /// then returns. This makes `stop(); start()` safe — the old thread is fully
    /// torn down before a new one is created.
    func stop() {
        guard let cfRunLoop = runLoop?.getCFRunLoop() else {
            return
        }

        // Queue the willStop callback and CFRunLoopStop via FIFO ordering.
        // All previously queued blocks (e.g. timer invalidations) complete first.
        // thread/runLoop are kept alive until onWillStop finishes so that isCurrent
        // and perform() still work correctly during teardown.
        let done = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            self?.onWillStop?()
            // Clear state after onWillStop so isCurrent was valid during teardown.
            self?.thread?.cancel()
            self?.thread = nil
            self?.runLoop = nil
        }
        CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.commonModes.rawValue) {
            CFRunLoopStop(cfRunLoop)
            done.signal()
        }
        CFRunLoopWakeUp(cfRunLoop)

        // Wait for the event thread to finish. The onWillStop callback only uses
        // DispatchQueue.main.async (non-blocking) and NSLock (no deadlock risk).
        done.wait()
    }

    // MARK: - Dispatch

    /// Schedule a block to run on the event thread.
    /// Returns `false` if the event thread is not running (block is not enqueued).
    @discardableResult
    func perform(_ block: @escaping () -> Void) -> Bool {
        guard let cfRunLoop = runLoop?.getCFRunLoop() else {
            return false
        }
        CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(cfRunLoop)
        return true
    }

    // MARK: - Timer

    /// Create a repeating or one-shot timer on the event thread's RunLoop.
    /// Returns `nil` if the event thread is not running.
    func scheduleTimer(
        interval: TimeInterval,
        repeats: Bool,
        handler: @escaping () -> Void
    ) -> EventThreadTimer? {
        guard let runLoop else {
            return nil
        }

        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
            handler()
        }
        runLoop.add(timer, forMode: .common)
        return EventThreadTimer(timer: timer, eventThread: self)
    }
}

// MARK: - EventThreadTimer

/// Lightweight wrapper around `Timer` that ensures invalidation happens on the correct thread.
///
/// When invalidated from the event thread, the underlying timer is stopped synchronously.
/// When invalidated from any other thread, invalidation is dispatched to the event thread.
/// On `deinit`, the timer is automatically invalidated — callers don't need manual cleanup.
final class EventThreadTimer {
    private var timer: Timer?
    private weak var eventThread: EventThread?

    init(timer: Timer, eventThread: EventThread) {
        self.timer = timer
        self.eventThread = eventThread
    }

    deinit {
        invalidate()
    }

    /// Invalidate the underlying timer. Safe to call from any thread and idempotent.
    func invalidate() {
        guard let timer else {
            return
        }
        self.timer = nil

        if let eventThread, eventThread.isCurrent {
            // Already on the event thread — invalidate synchronously.
            timer.invalidate()
        } else if let eventThread {
            // Dispatch to the event thread where the timer was installed.
            eventThread.perform {
                timer.invalidate()
            }
        }
        // If eventThread is nil (already deallocated), the RunLoop is gone
        // and the timer is implicitly dead.
    }

    var isValid: Bool {
        timer?.isValid ?? false
    }
}
