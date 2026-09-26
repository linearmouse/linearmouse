// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Foundation
import os.log

/// Makes a single left click on a window of an inactive app both activate the app and act on
/// the item under the pointer.
///
/// The original click is always forwarded untouched so the window server activates and raises
/// the clicked window. Once the target app has become frontmost, a synthetic left click is
/// replayed at the same location.
final class ClickThroughTransformer {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ClickThrough")

    typealias WindowLookup = (CGPoint) -> (ownerPid: pid_t, layer: Int)?
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

    static let dragThreshold: CGFloat = 4
    static let maximumClickDuration: TimeInterval = 0.5
    static let activationPollInterval: TimeInterval = 0.01
    static let activationPollAttempts = 30

    private struct PendingClick {
        let targetPid: pid_t
        let location: CGPoint
        let flags: CGEventFlags
        let pressedAt: TimeInterval
    }

    private let frontmostPid: () -> pid_t?
    private let windowAtPoint: WindowLookup
    private let ownPid: pid_t
    private let now: () -> TimeInterval
    private let schedule: Scheduler
    private let eventSink: (CGEvent) -> Void

    private let lock = NSLock()
    private var pendingClick: PendingClick?
    /// Incremented whenever a pending replay must be abandoned.
    private var generation = 0

    init(
        frontmostPid: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        windowAtPoint: @escaping WindowLookup = { WindowInfoCache.shared.topmostWindow(at: $0) },
        ownPid: pid_t = ProcessInfo.processInfo.processIdentifier,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedule: @escaping Scheduler = { delay, handler in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: handler)
        },
        eventSink: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    ) {
        self.frontmostPid = frontmostPid
        self.windowAtPoint = windowAtPoint
        self.ownPid = ownPid
        self.now = now
        self.schedule = schedule
        self.eventSink = eventSink
    }

    /// Whether a left mouse down on the given window should be replayed after activation.
    ///
    /// Only normal-level (layer 0) windows qualify, so clicks on the Dock, menu bar, status items
    /// and other overlays are left alone.
    static func shouldArm(windowOwnerPid: pid_t, layer: Int, frontmostPid: pid_t?, ownPid: pid_t) -> Bool {
        layer == 0 && windowOwnerPid != ownPid && windowOwnerPid != frontmostPid
    }
}

extension ClickThroughTransformer: EventTransformer {
    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        guard !event.isLinearMouseSyntheticEvent else {
            return event
        }

        switch event.type {
        case .leftMouseDown:
            handleMouseDown(event)
        case .leftMouseDragged:
            handleMouseDragged(event)
        case .leftMouseUp:
            handleMouseUp()
        default:
            break
        }

        return event
    }

    private func handleMouseDown(_ event: CGEvent) {
        lock.lock()
        // Any new press cancels a replay that has not been posted yet, so a real double-click
        // on an inactive window doesn't turn into three clicks.
        generation += 1
        pendingClick = nil
        lock.unlock()

        guard event.getIntegerValueField(.mouseEventClickState) <= 1,
              let window = windowAtPoint(event.location),
              Self.shouldArm(
                  windowOwnerPid: window.ownerPid,
                  layer: window.layer,
                  frontmostPid: frontmostPid(),
                  ownPid: ownPid
              ) else {
            return
        }

        lock.lock()
        pendingClick = PendingClick(
            targetPid: window.ownerPid,
            location: event.location,
            flags: event.flags,
            pressedAt: now()
        )
        lock.unlock()
    }

    private func handleMouseDragged(_ event: CGEvent) {
        lock.lock()
        defer { lock.unlock() }

        guard let pendingClick else {
            return
        }

        let dx = event.location.x - pendingClick.location.x
        let dy = event.location.y - pendingClick.location.y
        if dx * dx + dy * dy > Self.dragThreshold * Self.dragThreshold {
            self.pendingClick = nil
        }
    }

    private func handleMouseUp() {
        lock.lock()
        let pendingClick = pendingClick
        self.pendingClick = nil
        let generation = generation
        lock.unlock()

        guard let pendingClick,
              now() - pendingClick.pressedAt <= Self.maximumClickDuration else {
            return
        }

        waitForActivation(of: pendingClick, generation: generation, remainingAttempts: Self.activationPollAttempts)
    }

    private func waitForActivation(of click: PendingClick, generation: Int, remainingAttempts: Int) {
        schedule(Self.activationPollInterval) { [weak self] in
            guard let self else {
                return
            }

            lock.lock()
            let isCurrent = self.generation == generation
            lock.unlock()
            guard isCurrent else {
                return
            }

            if frontmostPid() == click.targetPid {
                replay(click)
            } else if remainingAttempts > 1 {
                waitForActivation(of: click, generation: generation, remainingAttempts: remainingAttempts - 1)
            } else {
                os_log(
                    "App %{public}d did not become frontmost; skipping click-through",
                    log: Self.log,
                    type: .info,
                    click.targetPid
                )
            }
        }
    }

    private func replay(_ click: PendingClick) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: click.location,
                mouseButton: .left
            ) else {
                return
            }
            event.flags = click.flags
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.isLinearMouseSyntheticEvent = true
            eventSink(event)
        }

        os_log("Replayed click-through for app %{public}d", log: Self.log, type: .info, click.targetPid)
    }
}

extension ClickThroughTransformer: Deactivatable {
    func deactivate() {
        lock.lock()
        generation += 1
        pendingClick = nil
        lock.unlock()
    }
}
