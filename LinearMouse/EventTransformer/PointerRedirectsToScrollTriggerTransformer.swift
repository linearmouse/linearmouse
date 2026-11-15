// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Foundation

/// Redirects pointer movement to scrolling only while a trigger button is held.
///
/// A quick press without movement is replayed as a normal click, so the button
/// keeps its own function. Once the pointer moves past a small tolerance, or the
/// button is held longer than a long press, the press is consumed: releasing it
/// then never clicks, even if nothing was scrolled.
final class PointerRedirectsToScrollTriggerTransformer {
    typealias Redirect = (CGEvent) -> Void
    typealias MonotonicClock = () -> UInt64

    /// Movement allowed before a press stops counting as a click. Matches the
    /// tolerance Auto Scroll uses to tell a click from a drag.
    static let clickMovementTolerance: Double = 10

    private struct DeferredEvent {
        var event: CGEvent
        var sink: (CGEvent) -> Void
    }

    private struct Pending {
        var button: CGMouseButton
        var press: DeferredEvent
        var pressedAt: UInt64
        var anchor: CGPoint
        var deltaX: Double = 0
        var deltaY: Double = 0
        var bufferedMoves: [CGEvent] = []

        var exceedsClickMovementTolerance: Bool {
            hypot(deltaX, deltaY) > PointerRedirectsToScrollTriggerTransformer.clickMovementTolerance
        }
    }

    private enum State {
        case idle
        /// The trigger is down but it is not yet known whether this is a click.
        case pending(Pending)
        /// The trigger is held and its press and release are consumed.
        case redirecting(CGMouseButton)
    }

    private let triggerButtonNumber: Int
    private let triggerModifierFlags: CGEventFlags
    private let redirect: Redirect
    private let warpPointer: (CGPoint) -> Void
    private let monotonicClock: MonotonicClock
    private let clickDurationNanoseconds: UInt64
    private let fallbackEventSink: (CGEvent) -> Void

    private var state = State.idle

    /// Returns nil unless `trigger` is a valid redirects-to-scroll trigger.
    init?(
        trigger: Scheme.Trigger,
        clickDuration: TimeInterval = ButtonMappingPolicy.default.longPressDuration,
        monotonicClock: @escaping MonotonicClock = { DispatchTime.now().uptimeNanoseconds },
        warpPointer: @escaping (CGPoint) -> Void = { CGWarpMouseCursorPosition($0) },
        eventSink: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) },
        redirect: @escaping Redirect = { PointerRedirectsToScrollTransformer.redirectToScroll($0) }
    ) {
        guard trigger.isValidRedirectsToScrollTrigger,
              case let .button(.mouse(buttonNumber)) = trigger.input else {
            return nil
        }

        triggerButtonNumber = buttonNumber
        triggerModifierFlags = trigger.modifierFlags
        clickDurationNanoseconds = UInt64(clickDuration * 1_000_000_000)
        self.monotonicClock = monotonicClock
        self.warpPointer = warpPointer
        fallbackEventSink = eventSink
        self.redirect = redirect
    }
}

extension PointerRedirectsToScrollTriggerTransformer: EventTransformer {
    var handlesPointerMotion: Bool {
        hasActiveInteraction
    }

    func needsDeferredEventContinuation(for event: CGEvent) -> Bool {
        // A replayed click must still pass through the later stages, such as
        // button mappings, so the button keeps its configured function.
        isMouseDown(event) || isMouseUp(event)
    }

    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard !SettingsState.shared.recording || hasActiveInteraction else {
            return event
        }

        if isMouseDown(event) {
            return handleMouseDown(event, in: context)
        }

        if isMouseUp(event) {
            return handleMouseUp(event, in: context)
        }

        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return handlePointerMoved(event)
        default:
            return event
        }
    }

    private func handleMouseDown(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        let button = MouseEventView(event).mouseButton

        switch state {
        case .idle:
            guard let button,
                  Int(button.rawValue) == triggerButtonNumber,
                  ModifierState.generic(from: event.flags) == triggerModifierFlags else {
                return event
            }

            state = .pending(.init(
                button: button,
                press: .init(
                    event: event.copy() ?? event,
                    sink: context.deferredEventSink ?? fallbackEventSink
                ),
                pressedAt: monotonicClock(),
                anchor: event.location
            ))
            return nil

        case let .pending(pending):
            // Pressing another button while holding the trigger uses it as a
            // hold, so its release must not click.
            if button != pending.button {
                state = .redirecting(pending.button)
            }
            return event

        case .redirecting:
            return event
        }
    }

    private func handleMouseUp(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        switch state {
        case .idle:
            return event

        case let .pending(pending):
            guard MouseEventView(event).mouseButton == pending.button else {
                return event
            }

            state = .idle
            let heldNanoseconds = monotonicClock() &- pending.pressedAt
            guard heldNanoseconds < clickDurationNanoseconds else {
                return nil
            }

            // Replay through the deferred sink so the press and release reach
            // the remaining stages and the system in order.
            pending.press.sink(pending.press.event)
            let releaseSink = context.deferredEventSink ?? fallbackEventSink
            releaseSink(event.copy() ?? event)
            return nil

        case let .redirecting(button):
            guard MouseEventView(event).mouseButton == button else {
                return event
            }

            state = .idle
            return nil
        }
    }

    private func handlePointerMoved(_ event: CGEvent) -> CGEvent? {
        switch state {
        case .idle:
            return event

        case var .pending(pending):
            pending.deltaX += event.getDoubleValueField(.mouseEventDeltaX)
            pending.deltaY += event.getDoubleValueField(.mouseEventDeltaY)
            pending.bufferedMoves.append(event.copy() ?? event)

            guard pending.exceedsClickMovementTolerance else {
                state = .pending(pending)
                // Dropping the event does not stop the cursor, so hold it at
                // the press location until the gesture is decided.
                warpPointer(pending.anchor)
                return nil
            }

            state = .redirecting(pending.button)
            for move in pending.bufferedMoves {
                redirect(move)
            }
            return nil

        case .redirecting:
            redirect(event)
            return nil
        }
    }

    private func isMouseDown(_ event: CGEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    private func isMouseUp(_ event: CGEvent) -> Bool {
        switch event.type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return true
        default:
            return false
        }
    }
}

extension PointerRedirectsToScrollTriggerTransformer: EventTransformerInteractionTracking {
    var hasActiveInteraction: Bool {
        if case .idle = state {
            return false
        }
        return true
    }
}

extension PointerRedirectsToScrollTriggerTransformer: Deactivatable {
    func deactivate() {
        state = .idle
    }
}
