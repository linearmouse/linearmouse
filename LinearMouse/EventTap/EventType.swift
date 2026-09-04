// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics

class EventType {
    /// Event types the global event tap always observes.
    ///
    /// Mouse drags and moves are intentionally excluded here. The event tap is
    /// synchronous, so every observed event costs a round trip through
    /// LinearMouse before WindowServer can deliver it. High polling-rate mice
    /// (4000–8000 Hz) emit thousands of drag events per second while a window
    /// is being dragged, which makes dragging visibly stutter unless those
    /// events are only observed when a feature actually needs them.
    static let base: [CGEventType] = [
        .scrollWheel,
        .leftMouseDown,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseUp,
        .otherMouseDown,
        .otherMouseUp,
        .keyDown,
        .keyUp,
        .flagsChanged
    ]

    static let mouseMoved: CGEventType = .mouseMoved

    /// The event types the global event tap needs in order to serve `schemes`.
    ///
    /// Drag events are only included for the buttons that some feature may
    /// need to observe while they are held (button mappings, primary/secondary
    /// button switching, universal back/forward, auto scroll and gesture
    /// buttons). `mouseMoved` is only included for features that track pointer
    /// movement without a button held.
    static func required(for schemes: [Scheme]) -> [CGEventType] {
        var draggedButtons = Set<CGMouseButton>()
        var needsMouseMoved = false

        for scheme in schemes {
            if scheme.pointer.redirectsToScroll ?? false {
                needsMouseMoved = true
            }

            if scheme.buttons.switchPrimaryButtonAndSecondaryButtons ?? false {
                draggedButtons.formUnion([.left, .right])
            }

            if let universalBackForward = scheme.buttons.universalBackForward {
                draggedButtons.formUnion(
                    UniversalBackForwardTransformer.interestedButtons(for: universalBackForward)
                )
            }

            for mapping in scheme.buttons.mappings ?? [] {
                draggedButtons.formUnion(mapping.mouseButtonsOfInterest)
            }

            if let autoScroll = scheme.buttons.$autoScroll, autoScroll.enabled ?? false {
                needsMouseMoved = true
                draggedButtons.formUnion(autoScroll.trigger?.mouseButtonsOfInterest ?? [.center])
            }

            if let gesture = scheme.buttons.$gesture, gesture.enabled ?? false {
                needsMouseMoved = true
                draggedButtons.formUnion(gesture.trigger?.mouseButtonsOfInterest ?? [.center])
            }
        }

        var eventTypes = base
        eventTypes += draggedButtons
            .map { $0.fixedCGEventType(of: .otherMouseDragged) }
            .sorted { $0.rawValue < $1.rawValue }
        if needsMouseMoved {
            eventTypes.append(mouseMoved)
        }
        return eventTypes
    }
}

private extension Scheme.Buttons.Mapping {
    /// The mouse buttons that may be held while this mapping is being
    /// recognized, i.e. the buttons whose drag events the mapping engine
    /// needs to see.
    var mouseButtonsOfInterest: Set<CGMouseButton> {
        guard let trigger = effectiveTrigger else {
            return []
        }

        var buttons = [Button]()
        if case let .button(button) = trigger.input {
            buttons.append(button)
        }
        buttons += trigger.simultaneous ?? []
        buttons += trigger.whileHeld ?? []

        return Set(buttons.compactMap { CGMouseButton(rawValue: UInt32(clamping: $0.syntheticMouseButtonNumber)) })
    }
}
