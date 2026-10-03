// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Foundation
import ObservationToken
import os.log

class GlobalEventTap {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "GlobalEventTap")

    static let shared = GlobalEventTap()

    private var observationToken: ObservationToken?
    private var motionObservationToken: ObservationToken?
    private let motionControl = EventTap.Control(isEnabled: false)
    private lazy var watchdog = GlobalEventTapWatchdog()
    private let eventThread = EventThread.shared
    private var shouldRun = false

    init() {}

    private func callback(_ event: CGEvent) -> CGEvent? {
        let manager = EventTransformerManager.shared
        if event.type.isPointerMotion {
            guard manager.pointerMotionRequirements.contains(eventType: event.type) else {
                return event
            }
        } else {
            PointerLocationTriggerController.shared.handle(event)
            ModifierState.shared.update(with: event)
        }

        let mouseEventView = MouseEventView(event)
        let usesProcessConditions = manager.usesProcessConditions
        let eventTransformerResolution = manager.resolve(
            withCGEvent: event,
            withSourcePid: mouseEventView.sourcePid,
            withTargetPid: usesProcessConditions ? mouseEventView.targetPid : nil,
            withMouseLocationPid: usesProcessConditions ? mouseEventView.mouseLocationOwnerPid : nil,
            withDisplay: ScreenManager.shared.currentScreenNameSnapshot
        )
        let transformedEvent = eventTransformerResolution.transform(event)
        invalidateWindowInfoCacheIfNeeded(for: event)
        return transformedEvent
    }

    private func invalidateWindowInfoCacheIfNeeded(for event: CGEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .leftMouseUp, .rightMouseUp, .otherMouseUp:
            WindowInfoCache.shared.invalidate()
        default:
            break
        }
    }

    func start() {
        shouldRun = true

        startObservation()
    }

    private func startObservation() {
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

        let eventTypes = EventType.all.filter { !$0.isPointerMotion }

        eventThread.onWillStop = {
            EventTransformerManager.shared.onPointerMotionRequirementsChanged = nil
            EventTransformerManager.shared.resetForRestart()
            WindowInfoCache.shared.invalidate()
        }
        eventThread.start()

        guard let observationResult = eventThread.performAndWait({ [self] in
            Result {
                let onInvalidated: () -> Void = { [weak self] in
                    DispatchQueue.main.async {
                        self?.restartIfNeeded(reason: "event tap invalidated")
                    }
                }
                let manager = EventTransformerManager.shared
                motionControl.isEnabled = !manager.pointerMotionRequirements.isEmpty
                manager.onPointerMotionRequirementsChanged = { [weak self] requirements in
                    self?.motionControl.isEnabled = !requirements.isEmpty
                }
                let motionToken = try EventTap.observe(
                    [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged],
                    onInvalidated: onInvalidated,
                    control: motionControl
                ) { [weak self] in self?.callback($1) }
                let token = try EventTap.observe(eventTypes, onInvalidated: onInvalidated) { [weak self] in
                    self?.callback($1)
                }
                return (token, motionToken)
            }
        }) else {
            eventThread.stop()
            return
        }

        switch observationResult {
        case let .success((token, motionToken)):
            observationToken = token
            motionObservationToken = motionToken
        case let .failure(error):
            eventThread.stop()
            NSAlert(error: error).runModal()
            return
        }

        watchdog.start()
    }

    func stop() {
        shouldRun = false
        stopObservation()
    }

    private func stopObservation() {
        // Release the observation token, which dispatches timer invalidation
        // to the event RunLoop (see EventTap.observe).
        observationToken = nil
        motionObservationToken = nil

        // EventThread.stop() fires onWillStop (which calls resetForRestart)
        // then stops the RunLoop, all in FIFO order.
        eventThread.stop()

        watchdog.stop()
    }

    private func restartIfNeeded(reason: StaticString) {
        guard shouldRun else {
            return
        }

        os_log("Restart GlobalEventTap: %{public}@", log: Self.log, type: .info, String(describing: reason))
        stopObservation()
        startObservation()
    }
}
