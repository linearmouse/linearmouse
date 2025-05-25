// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import Foundation
import ObservationToken
import os.log

class GlobalEventTap {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "GlobalEventTap")

    static let shared = GlobalEventTap()

    private var observationToken: ObservationToken?
    private lazy var watchdog = GlobalEventTapWatchdog()

    init() {}

    private func callback(_ event: CGEvent) -> CGEvent? {
        let mouseEventView = MouseEventView(event)
        let eventTransformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: mouseEventView.sourcePid,
            withTargetPid: mouseEventView.targetPid,
            withMouseLocationPid: mouseEventView.mouseLocationWindowID.ownerPid,
            withDisplay: ScreenManager.shared.currentScreenName
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
        if SchemeState.shared.schemes.contains(where: { $0.pointer.redirectsToScroll ?? false }) {
            eventTypes.append(EventType.mouseMoved)
        }

        do {
            observationToken = try EventTap.observe(eventTypes) { [weak self] in self?.callback($1) }
        } catch {
            NSAlert(error: error).runModal()
        }

        watchdog.start()
    }

    func stop() {
        observationToken = nil

        watchdog.stop()
    }
}
