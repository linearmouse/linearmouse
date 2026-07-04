// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Darwin
import Defaults
import Foundation

final class PointerLocationTriggerController {
    static let shared = PointerLocationTriggerController()

    private var trigger = PointerLocationDoubleModifierTrigger()
    private let indicatorController = PointerLocationIndicatorWindowController()

    private init() {}

    func handle(_ event: CGEvent) {
        guard Defaults[.showPointerLocation],
              !event.isLinearMouseSyntheticEvent else {
            trigger.reset()
            return
        }

        guard trigger.handle(event, triggerModifier: Defaults[.pointerLocationTriggerModifier]) else {
            return
        }

        DispatchQueue.main.async { [indicatorController] in
            indicatorController.show(at: NSEvent.mouseLocation)
        }
    }
}

struct PointerLocationDoubleModifierTrigger {
    private static let maximumTapDuration: TimeInterval = 0.35
    private static let maximumDoubleTapInterval: TimeInterval = 1

    private var previousFlags: CGEventFlags
    private var pendingTapStart: TimeInterval?
    private var firstTapTime: TimeInterval?

    init(initialFlags: CGEventFlags = []) {
        previousFlags = ModifierState.generic(from: initialFlags)
    }

    mutating func handle(_ event: CGEvent, triggerModifier: PointerLocationTriggerModifier) -> Bool {
        handle(
            eventType: event.type,
            flags: event.flags,
            timestamp: CGEventTimestampConverter.seconds(from: event.timestamp),
            triggerModifier: triggerModifier
        )
    }

    mutating func handle(
        eventType: CGEventType,
        flags: CGEventFlags,
        timestamp: TimeInterval,
        triggerModifier: PointerLocationTriggerModifier
    ) -> Bool {
        switch eventType {
        case .flagsChanged:
            return handleFlagsChanged(
                flags: flags,
                timestamp: timestamp,
                triggerModifier: triggerModifier
            )
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            reset()
            previousFlags = ModifierState.generic(from: flags)
            return false
        default:
            previousFlags = ModifierState.generic(from: flags)
            return false
        }
    }

    mutating func reset() {
        pendingTapStart = nil
        firstTapTime = nil
    }

    private mutating func handleFlagsChanged(
        flags: CGEventFlags,
        timestamp: TimeInterval,
        triggerModifier: PointerLocationTriggerModifier
    ) -> Bool {
        let currentFlags = ModifierState.generic(from: flags)
        defer {
            previousFlags = currentFlags
        }

        let triggerFlag = triggerModifier.flag
        let pressed = !previousFlags.contains(triggerFlag) && currentFlags == triggerFlag
        let released = previousFlags == triggerFlag && currentFlags.isEmpty

        if let firstTapTime,
           timestamp - firstTapTime > Self.maximumDoubleTapInterval {
            reset()
        }

        if pressed {
            pendingTapStart = timestamp
            return false
        }

        if released, let pendingTapStart {
            self.pendingTapStart = nil
            guard timestamp - pendingTapStart <= Self.maximumTapDuration else {
                reset()
                return false
            }
            return registerTap(at: timestamp)
        }

        if currentFlags != triggerFlag {
            reset()
        }

        return false
    }

    private mutating func registerTap(at timestamp: TimeInterval) -> Bool {
        guard let firstTapTime else {
            firstTapTime = timestamp
            return false
        }

        if timestamp - firstTapTime <= Self.maximumDoubleTapInterval {
            self.firstTapTime = nil
            return true
        }

        self.firstTapTime = timestamp
        return false
    }
}

private enum CGEventTimestampConverter {
    private static let timebase: mach_timebase_info_data_t = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return timebase
    }()

    static func seconds(from timestamp: CGEventTimestamp) -> TimeInterval {
        let nanoseconds = Double(timestamp) * Double(timebase.numer) / Double(timebase.denom)
        return nanoseconds / 1_000_000_000
    }
}
