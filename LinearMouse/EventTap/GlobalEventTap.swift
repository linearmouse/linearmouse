// MIT License
// Copyright (c) 2021-2024 LinearMouse

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

    private func callback(event: CGEvent) -> CGEvent? {
        let mouseEventView = MouseEventView(event)
        let eventTransformer = EventTransformerManager.shared.get(withCGEvent: event,
                                                                  withSourcePid: mouseEventView.sourcePid,
                                                                  withTargetPid: mouseEventView.targetPid)
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

        do {
            observationToken = try EventTap.observe([.scrollWheel,
                                                     .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                                     .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                                     .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                                                     .keyDown, .keyUp, .flagsChanged]) { [weak self] _, event in
                self?.callback(event: event)
            }
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
