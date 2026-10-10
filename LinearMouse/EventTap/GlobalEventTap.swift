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

    private var observationID = 0
    private lazy var recovery = EventTapRecovery(attempt: { [weak self] completion in
        guard let self else {
            return
        }
        let expectedObservationID = observationID
        AccessibilityPermission.check { [weak self] snapshot in
            guard let self, shouldRun, observationID == expectedObservationID else {
                return
            }
            guard snapshot.enabled else {
                completion(.permissionRequired)
                return
            }
            completion(startObservation() ? .started : .failed)
        }
    }, onFailure: { result in
        AccessibilityPermissionWindow.shared.show(eventTapFailed: result == .failed)
    })
    private let eventThread = EventThread.shared
    private var shouldRun = false
    /// Read and updated only on EventThread; disabled events never enter the focus controller.
    private var hoverFocusEnabled = false

    init() {}

    private func callback(_ event: CGEvent) -> CGEvent? {
        let manager = EventTransformerManager.shared
        if event.type.isPointerMotion {
            guard manager.pointerMotionRequirements.contains(eventType: event.type) else {
                if hoverFocusEnabled {
                    FocusFollowsMouseController.shared.observe(event)
                }
                return event
            }
        } else {
            if hoverFocusEnabled {
                FocusFollowsMouseController.shared.observe(event)
            }
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
        let wasMotion = event.type.isPointerMotion
        let transformedEvent = eventTransformerResolution.transform(event)
        if wasMotion, hoverFocusEnabled {
            if let transformedEvent, transformedEvent.type == .mouseMoved {
                FocusFollowsMouseController.shared.observe(transformedEvent)
            } else {
                FocusFollowsMouseController.shared.cancel()
            }
        }
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

        recovery.start()
    }

    private func startObservation() -> Bool {
        guard observationToken == nil else {
            return true
        }

        let eventTypes = EventType.all.filter { !$0.isPointerMotion }

        eventThread.onWillStop = {
            EventTransformerManager.shared.onPointerMotionRequirementsChanged = nil
            EventTransformerManager.shared.resetForRestart()
            FocusFollowsMouseController.shared.onEnabledChanged = nil
            FocusFollowsMouseController.shared.stop()
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
                let focusController = FocusFollowsMouseController.shared
                let updateMotionSubscription: () -> Void = { [weak self] in
                    guard let self else {
                        return
                    }
                    hoverFocusEnabled = focusController.isEnabled
                    motionControl.isEnabled = !manager.pointerMotionRequirements.isEmpty || hoverFocusEnabled
                }
                manager.onPointerMotionRequirementsChanged = { _ in updateMotionSubscription() }
                focusController.onEnabledChanged = updateMotionSubscription
                focusController.start()
                updateMotionSubscription()
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
            return false
        }

        switch observationResult {
        case let .success((token, motionToken)):
            observationToken = token
            motionObservationToken = motionToken
        case let .failure(error):
            eventThread.stop()
            os_log("Failed to create event tap: %{public}@", log: Self.log, type: .error, String(describing: error))
            return false
        }

        watchdog.start()
        AccessibilityPermissionWindow.shared.dismiss()
        return true
    }

    func stop() {
        shouldRun = false
        stopObservation()
    }

    private func stopObservation() {
        observationID += 1
        recovery.stop()
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
        recovery.start()
    }
}
