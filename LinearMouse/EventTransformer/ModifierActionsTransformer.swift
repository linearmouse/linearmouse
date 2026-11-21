// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Carbon
import Foundation
import GestureKit
import KeyKit
import os.log

class ModifierActionsTransformer {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ModifierActionsTransformer"
    )

    private static let defaultKeySimulator = KeySimulator(
        eventSourceUserData: CGEvent.linearMouseSyntheticEventUserData
    )

    static let zoomShortcutResolver = KeyEquivalentResolver(keyEquivalents: ["+", "-"])

    typealias Modifiers = Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Modifiers>
    typealias Action = Scheme.Scrolling.Modifiers.Action

    private let modifiers: Modifiers
    private let keySimulator: KeySimulating
    private let zoomSteps: ScrollActionRecognizer
    private let highResolutionWheelMultiplier: (EventTransformerContext) -> Int?
    private let monotonicClock: () -> UInt64
    private let zoomShortcut: (Bool) -> KeyEquivalentResolver.Shortcut?

    private var pinchZoomBegan = false
    private var pinchZoomReversed = false

    init(
        modifiers: Modifiers,
        keySimulator: KeySimulating? = nil,
        scrollGesture: ScrollGestureOwnership = .init(),
        highResolutionWheelMultiplier: @escaping (EventTransformerContext) -> Int? = { _ in nil },
        monotonicClock: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        zoomShortcut: @escaping (Bool) -> KeyEquivalentResolver.Shortcut? = defaultZoomShortcut
    ) {
        self.modifiers = modifiers
        self.keySimulator = keySimulator ?? Self.defaultKeySimulator
        // Zoom is an incremental control like volume: it steps with the
        // movement instead of sharing the discrete-command cooldown.
        zoomSteps = ScrollActionRecognizer(gesture: scrollGesture)
        self.highResolutionWheelMultiplier = highResolutionWheelMultiplier
        self.monotonicClock = monotonicClock
        self.zoomShortcut = zoomShortcut
    }

    static func defaultZoomShortcut(zoomIn: Bool) -> KeyEquivalentResolver.Shortcut? {
        if #available(macOS 12, *) {
            return zoomShortcutResolver.shortcut(for: zoomIn ? "+" : "-")
        }
        // Preserve the legacy behavior on systems without AppKit's automatic shortcut localization.
        return .init(
            keyCode: CGKeyCode(zoomIn ? kVK_ANSI_KeypadPlus : kVK_ANSI_KeypadMinus),
            modifierFlags: .maskCommand
        )
    }
}

extension ModifierActionsTransformer: EventTransformer {
    var handlesPointerMotion: Bool {
        false
    }

    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        if pinchZoomBegan {
            return handlePinchZoom(event, reverse: pinchZoomReversed)
        }

        guard event.type == .scrollWheel else {
            return event
        }

        let scrollWheelEventView = ScrollWheelEventView(event)
        // Movement-free gesture boundaries never reach the zoom action below,
        // but must still end the previous gesture's zoom progress.
        if scrollWheelEventView.deltaYSignum == 0, scrollWheelEventView.deltaXSignum == 0,
           [.began, .ended, .cancelled].contains(scrollWheelEventView.scrollPhase) {
            zoomSteps.discardMovement()
        }
        guard let modifiers = scrollWheelEventView.deltaYSignum != 0
            ? modifiers.vertical
            : modifiers.horizontal else {
            return event
        }

        let actions: [(CGEventFlags.Element, Action?)] = [
            (.maskCommand, modifiers.command),
            (.maskShift, modifiers.shift),
            (.maskAlternate, modifiers.option),
            (.maskControl, modifiers.control)
        ]
        var event = event
        for case let (flag, action) in actions where event.flags.contains(flag) {
            if let action, action != .auto {
                guard let handledEvent = handleModifierKeyAction(for: event, action: action, in: context) else {
                    return nil
                }
                event = handledEvent
                event.flags.remove(flag)
            }
        }
        return event
    }

    private func handleModifierKeyAction(
        for event: CGEvent,
        action: Action,
        in context: EventTransformerContext
    ) -> CGEvent? {
        let scrollWheelEventView = ScrollWheelEventView(event)

        switch action {
        case .auto, .ignore:
            break
        case .preventDefault:
            return nil
        case .alterOrientation:
            scrollWheelEventView.swapXY()
        case let .changeSpeed(scale: scale):
            scrollWheelEventView.scale(factor: scale.asTruncatedDouble)
        case .zoom, .zoomReversed:
            let scrollWheelEventView = ScrollWheelEventView(event)
            var deltaSignum = scrollWheelEventView.deltaYSignum != 0 ? scrollWheelEventView
                .deltaYSignum : scrollWheelEventView.deltaXSignum
            if action == .zoomReversed {
                deltaSignum *= -1
            }
            if deltaSignum == 0 {
                return event
            }
            guard scrollWheelEventView.momentumPhase == .none else {
                return nil
            }
            let axis: ScrollInput.Axis = scrollWheelEventView.deltaYSignum != 0 ? .vertical : .horizontal
            let steps = zoomSteps(for: scrollWheelEventView, axis: axis, flags: event.flags, in: context)
            let restoringModifierFlags = ModifierState.normalize(event.flags)
            if steps > 0, let shortcut = zoomShortcut(deltaSignum > 0) {
                for _ in 0 ..< steps {
                    try? keySimulator.press(
                        keyCode: shortcut.keyCode,
                        modifierFlags: shortcut.modifierFlags,
                        restoringModifierFlags: restoringModifierFlags,
                        tap: .cgSessionEventTap
                    )
                }
            }
            return nil
        case .pinchZoom:
            pinchZoomReversed = false
            return handlePinchZoom(event, reverse: false)
        case .pinchZoomReversed:
            pinchZoomReversed = true
            return handlePinchZoom(event, reverse: true)
        }

        return event
    }

    /// One step per wheel event or high-resolution detent, and one per 32 pt
    /// of continuous input (trackpads, Magic Mouse, pixel-distance scrolling).
    private func zoomSteps(
        for view: ScrollWheelEventView,
        axis: ScrollInput.Axis,
        flags: CGEventFlags,
        in context: EventTransformerContext
    ) -> Int {
        zoomSteps.updateModifiers(flags.rawValue)
        if view.scrollPhase == .began {
            zoomSteps.beginGesture()
        }
        defer {
            if view.scrollPhase == .ended || view.scrollPhase == .cancelled {
                zoomSteps.endGesture()
            }
        }
        guard view.scrollPhase != .cancelled,
              let input = ScrollInput.read(
                  from: view,
                  highResolutionMultiplier: highResolutionWheelMultiplier(context),
                  axis: axis
              ) else {
            return 0
        }
        return zoomSteps.consume(input, mapping: 0, policy: .steps, at: monotonicClock())
    }

    private func handlePinchZoom(_ event: CGEvent, reverse: Bool) -> CGEvent? {
        guard event.type == .scrollWheel || event.type == .flagsChanged else {
            return event
        }

        if event.type == .flagsChanged {
            pinchZoomBegan = false
            pinchZoomReversed = false
            GestureEvent(zoomSource: nil, phase: .ended, magnification: 0)?.post(tap: .cgSessionEventTap)
            os_log("pinch zoom ended", log: Self.log, type: .info)
            return event
        }

        if !pinchZoomBegan {
            GestureEvent(zoomSource: nil, phase: .began, magnification: 0)?.post(tap: .cgSessionEventTap)
            pinchZoomBegan = true
            os_log("pinch zoom began", log: Self.log, type: .info)
        }

        let scrollWheelEventView = ScrollWheelEventView(event)
        let direction = reverse ? -1.0 : 1.0
        let magnification = Double(scrollWheelEventView.deltaYPt) * 0.005 * direction
        GestureEvent(zoomSource: nil, phase: .changed, magnification: magnification)?.post(tap: .cgSessionEventTap)
        os_log("pinch zoom changed: magnification=%f", log: Self.log, type: .info, magnification)

        return nil
    }
}

extension ModifierActionsTransformer: Deactivatable {
    func deactivate() {
        if pinchZoomBegan {
            pinchZoomBegan = false
            pinchZoomReversed = false
            GestureEvent(zoomSource: nil, phase: .ended, magnification: 0)?.post(tap: .cgSessionEventTap)
            os_log("ModifierActionsTransformer is inactive, pinch zoom ended", log: Self.log, type: .info)
        }
    }
}
