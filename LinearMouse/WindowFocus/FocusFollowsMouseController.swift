// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit

/// The event tap only replaces a small snapshot. AX IPC, hit testing and the
/// private focus protocol run on a serial worker, at most once per 25 ms.
final class FocusFollowsMouseController {
    static let shared = FocusFollowsMouseController()

    /// Set/called on EventThread, like EventTap.Control.
    var onEnabledChanged: (() -> Void)?

    private struct Input {
        let point: CGPoint
        let senderID: UInt64
        let sequence: UInt64
    }

    private let lock = NSLock()
    private var enabled = false
    private var running = false
    private var systemSuspended = false
    private var input: Input?
    private var revision: UInt64 = 0
    private var sequence: UInt64 = 0

    private let queue = DispatchQueue(label: "app.linearmouse.hover-focus", qos: .userInitiated)
    // Worker-only state.
    private var configuration = Configuration()
    private var timer: DispatchSourceTimer?
    private var state = HoverFocusState()
    private var lastRevision: UInt64 = 0
    private var lastSequence: UInt64 = 0
    private var previousFocus: HoverWindowQuery.Focus?
    private let query = HoverWindowQuery()
    // Main-thread-only observation.
    private var systemObserver: HoverFocusSystemObserver?

    var isEnabled: Bool {
        lock.withLock { enabled }
    }

    func configure(_ configuration: Configuration) {
        lock.withLock {
            enabled = configuration.schemes.contains { $0.pointer.focusFollowsMouse == true }
            revision &+= 1
            input = nil
        }
        queue.async { [self] in
            self.configuration = configuration
            state = HoverFocusState()
            previousFocus = nil
            updateTimer()
        }
        updateSystemObservation()
        onEnabledChanged?()
    }

    func start() {
        lock.withLock { running = true }
        queue.async { [self] in updateTimer() }
        updateSystemObservation()
    }

    func stop() {
        lock.withLock {
            running = false
            revision &+= 1
            input = nil
        }
        queue.async { [self] in
            updateTimer()
            state = HoverFocusState()
            previousFocus = nil
        }
        updateSystemObservation()
    }

    func cancel() {
        lock.withLock {
            revision &+= 1
            input = nil
        }
    }

    func observe(_ event: CGEvent) {
        guard isEnabled else {
            return
        }
        guard event.type == .mouseMoved,
              !event.isLinearMouseSyntheticEvent,
              event.getIntegerValueField(.eventSourceUnixProcessID) == 0,
              event.flags.isDisjoint(with: Self.pauseFlags),
              let hidEvent = CGEventCopyIOHIDEvent(event) else {
            cancel()
            return
        }
        let senderID = IOHIDEventGetSenderID(hidEvent)
        guard senderID != 0 else {
            cancel()
            return
        }
        lock.withLock {
            guard running, !systemSuspended else {
                return
            }
            sequence &+= 1
            input = Input(point: event.location, senderID: senderID, sequence: sequence)
        }
    }

    private static let pauseFlags: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate, .maskShift]

    private func updateTimer() {
        timer?.cancel()
        timer = nil
        guard lock.withLock({ running && enabled && !systemSuspended }) else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(25), leeway: .milliseconds(5))
        // Dispatch sources coalesce missed ticks and never invoke this handler
        // concurrently. Process only the latest input, never the missed-tick count.
        timer.setEventHandler { [weak self] in self?.poll() }
        self.timer = timer
        timer.resume()
    }

    private func poll() {
        let (input, revision) = lock.withLock { (self.input, self.revision) }
        if revision != lastRevision {
            state.suspend()
            lastRevision = revision
            previousFocus = nil
        }
        guard let input, input.sequence != lastSequence || state.isWaiting else {
            return
        }
        lastSequence = input.sequence
        guard inputIsCurrent(input, revision: revision),
              let device = DeviceManager.shared.identifiedDevice(for: input.senderID),
              let window = query.window(at: input.point) else {
            _ = state.update(nil)
            return
        }
        let process = window.pid.processIdentity
        let scheme = configuration.matchScheme(
            withDevice: device,
            withProcess: process,
            withDisplay: ScreenManager.shared.displayName(at: input.point)
        )
        guard scheme.pointer.focusFollowsMouse == true,
              scheme.pointer.redirectsToScroll != true || scheme.pointer.redirectsToScrollTrigger != nil else {
            _ = state.update(nil)
            return
        }

        let target = HoverFocusState.Target(windowID: window.windowID, pid: window.pid, senderID: input.senderID)
        let ready = state.update(target)
        guard ready else {
            return
        }
        guard query.canFocus(window, at: input.point), let focus = query.currentFocus() else {
            state.suspend()
            return
        }
        if let previousFocus, previousFocus != focus {
            // Includes switching windows within the same app. Remember the
            // hovered window but require re-entry before taking focus back.
            state.suspend()
        }
        previousFocus = focus
        guard ready, state.isWaiting, focus != .init(pid: window.pid, windowID: window.windowID) else {
            if focus == .init(pid: window.pid, windowID: window.windowID) {
                state.suspend()
            }
            return
        }

        // AX calls can take time. Recheck the input and focused window after
        // hit testing, and only then perform this entry's one focus attempt.
        guard inputIsCurrent(input, revision: revision), query.currentFocus() == focus,
              query.window(at: input.point) == window,
              inputIsCurrent(input, revision: revision) else {
            return
        }
        state.suspend()
        if WindowFocus.shared.focus(window, from: focus, isCurrent: {
            // Movement inside the same window is still valid; crossing to C,
            // clicking, disabling or suspending invalidates the old request.
            guard let latest = self.lock.withLock({ self.input }), latest.senderID == input.senderID,
                  self.inputIsCurrent(latest, revision: revision),
                  self.query.window(at: latest.point) == window else {
                return false
            }
            return self.inputIsCurrent(latest, revision: revision)
        }) {
            previousFocus = .init(pid: window.pid, windowID: window.windowID)
        } else {
            // The old window may already have received deactivation. Let the
            // next window entry establish the current focus afresh.
            previousFocus = nil
        }
    }

    private func inputIsCurrent(_ captured: Input, revision: UInt64) -> Bool {
        let valid = lock.withLock {
            running && enabled && !systemSuspended && self.revision == revision &&
                input?.point == captured.point && input?.senderID == captured.senderID
        }
        guard valid, CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: Self.pauseFlags) else {
            return false
        }
        return !(0 ..< 32).contains {
            CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32($0))!)
        }
    }

    private func updateSystemObservation() {
        DispatchQueue.main.async { [self] in
            if lock.withLock({ running && enabled }) {
                if systemObserver == nil {
                    systemObserver = HoverFocusSystemObserver { [weak self] suspended in
                        guard let self else {
                            return
                        }
                        lock.withLock {
                            if let suspended {
                                self.systemSuspended = suspended
                            }
                            self.revision &+= 1
                            self.input = nil
                        }
                        if suspended != nil {
                            self.queue.async { self.updateTimer() }
                        }
                    }
                }
            } else {
                systemObserver = nil
                lock.withLock { systemSuspended = false }
            }
        }
    }
}
