// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Foundation

/// Redirects pointer movement to scrolling only while a trigger button is held.
///
/// The trigger press and release are consumed so the button does not click.
final class PointerRedirectsToScrollTriggerTransformer {
    typealias Redirect = (CGEvent) -> Void

    private let triggerButtonNumber: Int
    private let triggerModifierFlags: CGEventFlags
    private let redirect: Redirect

    /// The trigger button that is currently held down.
    private var heldButton: CGMouseButton?

    /// Returns nil unless `trigger` is a valid redirects-to-scroll trigger.
    init?(
        trigger: Scheme.Trigger,
        redirect: @escaping Redirect = PointerRedirectsToScrollTransformer.redirectToScroll
    ) {
        guard trigger.isValidRedirectsToScrollTrigger,
              case let .button(.mouse(buttonNumber)) = trigger.input else {
            return nil
        }

        triggerButtonNumber = buttonNumber
        triggerModifierFlags = trigger.modifierFlags
        self.redirect = redirect
    }
}

extension PointerRedirectsToScrollTriggerTransformer: EventTransformer {
    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        guard !SettingsState.shared.recording || hasActiveInteraction else {
            return event
        }

        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard heldButton == nil,
                  let button = MouseEventView(event).mouseButton,
                  Int(button.rawValue) == triggerButtonNumber,
                  ModifierState.generic(from: event.flags) == triggerModifierFlags else {
                return event
            }

            heldButton = button
            return nil

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard let heldButton,
                  MouseEventView(event).mouseButton == heldButton else {
                return event
            }

            self.heldButton = nil
            return nil

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard hasActiveInteraction else {
                return event
            }

            redirect(event)
            return nil

        default:
            return event
        }
    }
}

extension PointerRedirectsToScrollTriggerTransformer: EventTransformerInteractionTracking {
    var hasActiveInteraction: Bool {
        heldButton != nil
    }
}

extension PointerRedirectsToScrollTriggerTransformer: Deactivatable {
    func deactivate() {
        heldButton = nil
    }
}
