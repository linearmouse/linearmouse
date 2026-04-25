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
    private lazy var watchdog = GlobalEventTapWatchdog()
    private let eventThread = EventThread.shared

    init() {}

    private func callback(_ event: CGEvent) -> CGEvent? {
        ModifierState.shared.update(with: event)

        let mouseEventView = MouseEventView(event)
        let usesProcessConditions = ConfigurationState.shared.configuration.usesProcessConditions
        let eventTransformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: mouseEventView.sourcePid,
            withTargetPid: usesProcessConditions ? mouseEventView.targetPid : nil,
            withMouseLocationPid: usesProcessConditions ? mouseEventView.mouseLocationOwnerPid : nil,
            withDisplay: ScreenManager.shared.currentScreenNameSnapshot
        )
        let transformedEvent = eventTransformer.transform(event)
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

        eventThread.onWillStop = {
            EventTransformerManager.shared.resetForRestart()
            WindowInfoCache.shared.invalidate()
        }
        eventThread.start()

        guard let observationResult = eventThread.performAndWait({
            Result {
                try EventTap.observe(eventTypes) { [weak self] in self?.callback($1) }
            }
        }) else {
            eventThread.stop()
            return
        }

        switch observationResult {
        case let .success(token):
            observationToken = token
        case let .failure(error):
            eventThread.stop()
            NSAlert(error: error).runModal()
            return
        }

        watchdog.start()
    }

    func stop() {
        // Release the observation token, which dispatches timer invalidation
        // to the event RunLoop (see EventTap.observe).
        observationToken = nil

        // EventThread.stop() fires onWillStop (which calls resetForRestart)
        // then stops the RunLoop, all in FIFO order.
        eventThread.stop()

        watchdog.stop()
    }
}
