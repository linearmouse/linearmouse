// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Foundation
import ObservationToken
import os.log

class GlobalEventTap {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "GlobalEventTap")

    static let shared = GlobalEventTap()

    /// The RunLoop running on the dedicated event processing thread.
    /// All transformer state access (transform, tick, deactivate) must happen on this RunLoop's thread.
    static var processingRunLoop: RunLoop? {
        shared._processingRunLoop
    }

    /// Schedule a block to run on the event processing thread.
    /// Use this from other threads (e.g. Logitech HID thread) to serialize transformer state access.
    /// Returns `false` if the event thread is not running (block is not enqueued).
    @discardableResult
    static func performOnEventThread(_ block: @escaping () -> Void) -> Bool {
        guard let cfRunLoop = shared._processingRunLoop?.getCFRunLoop() else {
            return false
        }
        CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(cfRunLoop)
        return true
    }

    private var observationToken: ObservationToken?
    private lazy var watchdog = GlobalEventTapWatchdog()

    /// Background thread dedicated to the CGEvent tap RunLoop.
    private var eventThread: Thread?

    /// The RunLoop running on the background event thread.
    private var _processingRunLoop: RunLoop?
    private let runLoopReady = DispatchSemaphore(value: 0)

    init() {}

    private func callback(_ event: CGEvent) -> CGEvent? {
        ModifierState.shared.update(with: event)

        let mouseEventView = MouseEventView(event)
        let eventTransformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: mouseEventView.sourcePid,
            withTargetPid: mouseEventView.targetPid,
            withMouseLocationPid: mouseEventView.mouseLocationWindowID.ownerPid,
            withDisplay: ScreenManager.shared.atomicCurrentScreenName
        )
        return eventTransformer.transform(event)
    }

    func start() {
        guard observationToken == nil else {
            return
        }

        guard AccessibilityPermission.enabled else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "Failed to create GlobalEventTap: Accessibility permission not granted",
                comment: ""
            )
            alert.runModal()
            return
        }

        var eventTypes: [CGEventType] = EventType.all
        if SchemeState.shared.schemes.contains(where: { $0.pointer.redirectsToScroll ?? false }) ||
            SchemeState.shared.schemes.contains(where: { $0.buttons.$autoScroll?.enabled ?? false }) ||
            SchemeState.shared.schemes.contains(where: { $0.buttons.$gesture?.enabled ?? false }) {
            eventTypes.append(EventType.mouseMoved)
        }

        // Start the background event thread with its own RunLoop.
        let thread = Thread { [weak self] in
            guard let self else {
                return
            }
            let runLoop = RunLoop.current
            // Add a keep-alive port so the RunLoop doesn't exit before the event tap source is added.
            runLoop.add(Port(), forMode: .common)
            self._processingRunLoop = runLoop
            self.runLoopReady.signal()
            CFRunLoopRun()
        }
        thread.name = "com.linearmouse.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        eventThread = thread

        runLoopReady.wait()

        guard let processingRunLoop = _processingRunLoop else {
            return
        }

        do {
            observationToken = try EventTap.observe(
                eventTypes,
                at: processingRunLoop
            ) { [weak self] in self?.callback($1) }
        } catch {
            // Clean up the event thread that was just created.
            CFRunLoopStop(processingRunLoop.getCFRunLoop())
            eventThread?.cancel()
            eventThread = nil
            _processingRunLoop = nil

            NSAlert(error: error).runModal()
            return
        }

        watchdog.start()
    }

    func stop() {
        // Release the observation token, which dispatches timer invalidation
        // to the event RunLoop (see EventTap.observe).
        observationToken = nil

        if let cfRunLoop = _processingRunLoop?.getCFRunLoop() {
            // Queue RunLoop stop after any pending cleanup blocks (FIFO ordering).
            CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(cfRunLoop)
            }
            CFRunLoopWakeUp(cfRunLoop)
        }
        eventThread?.cancel()
        eventThread = nil
        _processingRunLoop = nil

        watchdog.stop()
    }
}
