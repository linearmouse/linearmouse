// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics

extension Scheme.Buttons.Mapping {
    enum ButtonUsageRisk: Equatable {
        case singleButtonLongPress(button: Button)
        case simultaneousPrimaryChord(recommendedHeldButton: Button?)
        case primaryHeldPrefix
    }

    typealias Trigger = Scheme.Trigger

    enum Modifier: String, Codable, CaseIterable, Equatable, Hashable {
        case command
        case shift
        case option
        case control

        var flag: CGEventFlags {
            switch self {
            case .command:
                return .maskCommand
            case .shift:
                return .maskShift
            case .option:
                return .maskAlternate
            case .control:
                return .maskControl
            }
        }

        var sortOrder: Int {
            switch self {
            case .control:
                return 0
            case .option:
                return 1
            case .shift:
                return 2
            case .command:
                return 3
            }
        }
    }

    struct Outcomes: Codable, Equatable, Hashable {
        /// An action that begins as soon as the trigger resolves. Unlike a
        /// short press, it owns a pressed/released lifecycle and can therefore
        /// repeat, hold keys, or remap a complete mouse-button event stream.
        var press: PressAction?
        var shortPress: Action?
        var longPress: Action?
        var swipe: SwipeActions?

        init(
            press: PressAction? = nil,
            shortPress: Action? = nil,
            longPress: Action? = nil,
            swipe: SwipeActions? = nil
        ) {
            self.press = press
            self.shortPress = shortPress
            self.longPress = longPress
            self.swipe = swipe?.isEmpty == true ? nil : swipe
        }

        var isEmpty: Bool {
            press == nil && shortPress == nil && longPress == nil && swipe?.isEmpty != false
        }

        var isLongPressOnly: Bool {
            press == nil && shortPress == nil && longPress != nil && swipe?.isEmpty != false
        }

        var hasDeferredOutcome: Bool {
            shortPress != nil || longPress != nil || swipe?.isEmpty == false
        }
    }

    struct PressAction: Codable, Equatable, Hashable {
        var action: Action
        var behavior: Behavior

        init(action: Action, behavior: Behavior = .perform) {
            self.action = action
            self.behavior = behavior
        }

        enum Behavior: String, Codable, CaseIterable, Equatable, Hashable {
            /// Execute once when the trigger resolves.
            case perform
            /// Execute immediately, then follow the system key-repeat cadence until release.
            case `repeat`
            /// Hold a key-press action down until the trigger is released.
            case hold
            /// Rewrite the complete down/drag/up stream as another mouse button.
            case remap
        }
    }

    struct SwipeActions: Codable, Equatable, Hashable {
        var up: Action?
        var down: Action?
        var left: Action?
        var right: Action?

        init(up: Action? = nil, down: Action? = nil, left: Action? = nil, right: Action? = nil) {
            self.up = up
            self.down = down
            self.left = left
            self.right = right
        }

        var isEmpty: Bool {
            up == nil && down == nil && left == nil && right == nil
        }
    }
}

extension Scheme.Trigger {
    func valid(with outcomes: Scheme.Buttons.Mapping.Outcomes?) -> Bool {
        let canonicalized = canonicalized

        guard canonicalized.simultaneous?.containsInput(canonicalized.input) != true,
              canonicalized.whileHeld?.containsInput(canonicalized.input) != true,
              Set(canonicalized.simultaneous ?? []).isDisjoint(with: canonicalized.whileHeld ?? []) else {
            return false
        }

        switch canonicalized.input {
        case let .button(button):
            let hasOtherButtons = canonicalized.simultaneous?.isEmpty == false ||
                canonicalized.whileHeld?.isEmpty == false
            let isUnmodifiedStandalonePrimary = button.mouseButtonNumber == 0 &&
                !hasOtherButtons && canonicalized.modifierFlags.isEmpty
            guard !isUnmodifiedStandalonePrimary || outcomes?.isLongPressOnly == true else {
                return false
            }

            guard outcomes?.press == nil || outcomes?.hasDeferredOutcome == false else {
                return false
            }

            guard let press = outcomes?.press else {
                return true
            }

            switch press.behavior {
            case .perform, .repeat:
                return true
            case .hold:
                guard case .arg1(.keyPress) = press.action else {
                    return false
                }
                return true
            case .remap:
                return canonicalized.chordButtons.count == 1 &&
                    canonicalized.whileHeld == nil &&
                    button.mouseButtonNumber != nil &&
                    press.action.remappedMouseButton != nil
            }

        case .wheel:
            guard canonicalized.simultaneous == nil,
                  outcomes?.isEmpty != false else {
                return false
            }

            return true
        }
    }
}

extension Scheme.Buttons.Mapping {
    var isStructured: Bool {
        trigger != nil
    }

    var effectiveTrigger: Trigger? {
        if let trigger {
            return trigger
        }

        let modifiers = Modifier.allCases.filter { modifierFlags.contains($0.flag) }
        if let button {
            return .init(input: .button(button), modifiers: modifiers)
        }
        if let scroll {
            return .init(input: .wheel(scroll), modifiers: modifiers)
        }
        return nil
    }

    /// Describes delayed native button behavior worth calling out in the editor.
    /// Ordered triggers whose input is Primary are intentionally excluded: they
    /// cannot match until their held prefix is already down, so an ordinary
    /// Primary click remains untouched.
    var buttonUsageRisk: ButtonUsageRisk? {
        guard let trigger = effectiveTrigger else {
            return nil
        }

        let primaryButton = Button.mouse(0)
        let heldButtons = Set(trigger.whileHeld ?? [])
        if trigger.modifierFlags.isEmpty, heldButtons.contains(primaryButton) {
            return .primaryHeldPrefix
        }

        if trigger.modifierFlags.isEmpty,
           heldButtons.isEmpty,
           trigger.chordButtons.count > 1,
           trigger.chordButtons.contains(primaryButton) {
            let recommendedHeldButton: Button? = if let relationship = trigger.twoButtonRelationship {
                relationship.first == primaryButton ? relationship.second : relationship.first
            } else {
                nil
            }
            return .simultaneousPrimaryChord(recommendedHeldButton: recommendedHeldButton)
        }

        guard heldButtons.isEmpty,
              trigger.chordButtons.count == 1,
              outcomes?.longPress != nil,
              case let .button(button) = trigger.input else {
            return nil
        }
        return .singleButtonLongPress(button: button)
    }

    var immediateAction: Action? {
        guard let trigger else {
            return scroll == nil ? nil : action
        }
        guard case .wheel = trigger.input else {
            return nil
        }
        return action
    }

    mutating func normalizeAsStructured() {
        guard trigger == nil, let effectiveTrigger else {
            return
        }

        let wasButton = button != nil
        let legacyAction = action ?? .arg0(.auto)
        let repeats = `repeat` == true
        let holdsKeys = legacyAction.shouldHoldKeys(explicitly: hold == true)
        let remapsButton = !repeats && button?.mouseButtonNumber != nil &&
            legacyAction.remappedMouseButton != nil
        trigger = effectiveTrigger
        if wasButton {
            if holdsKeys {
                outcomes = .init(press: .init(action: legacyAction, behavior: .hold))
            } else if repeats {
                outcomes = .init(press: .init(action: legacyAction, behavior: .repeat))
            } else if remapsButton {
                outcomes = .init(press: .init(action: legacyAction, behavior: .remap))
            } else {
                outcomes = .init(shortPress: legacyAction)
            }
            action = nil
        } else if action == nil {
            action = .arg0(.auto)
        }

        button = nil
        scroll = nil
        command = nil
        shift = nil
        option = nil
        control = nil
        `repeat` = nil
        hold = nil
    }

    func hasOverlappingOutcome(with other: Self) -> Bool {
        guard let trigger, let otherTrigger = other.trigger,
              trigger.isEquivalent(to: otherTrigger) else {
            return false
        }

        if case .wheel = trigger.input {
            return action != nil && other.action != nil
        }

        if outcomes?.press != nil || other.outcomes?.press != nil {
            return outcomes?.isEmpty == false && other.outcomes?.isEmpty == false
        }

        return outcomes?.shortPress != nil && other.outcomes?.shortPress != nil ||
            outcomes?.longPress != nil && other.outcomes?.longPress != nil ||
            outcomes?.swipe?.up != nil && other.outcomes?.swipe?.up != nil ||
            outcomes?.swipe?.down != nil && other.outcomes?.swipe?.down != nil ||
            outcomes?.swipe?.left != nil && other.outcomes?.swipe?.left != nil ||
            outcomes?.swipe?.right != nil && other.outcomes?.swipe?.right != nil
    }

    mutating func mergeOutcomes(from other: Self) {
        guard let trigger, let otherTrigger = other.trigger,
              trigger.isEquivalent(to: otherTrigger) else {
            return
        }

        if case .wheel = trigger.input {
            action = other.action ?? action
            return
        }

        if outcomes?.press != nil || other.outcomes?.press != nil {
            outcomes = other.outcomes
            return
        }

        var merged = outcomes ?? .init()
        merged.shortPress = other.outcomes?.shortPress ?? merged.shortPress
        merged.longPress = other.outcomes?.longPress ?? merged.longPress
        var swipe = merged.swipe ?? .init()
        swipe.up = other.outcomes?.swipe?.up ?? swipe.up
        swipe.down = other.outcomes?.swipe?.down ?? swipe.down
        swipe.left = other.outcomes?.swipe?.left ?? swipe.left
        swipe.right = other.outcomes?.swipe?.right ?? swipe.right
        merged.swipe = swipe.isEmpty ? nil : swipe
        outcomes = merged
    }
}

private extension Array where Element == Scheme.Buttons.Mapping.Button {
    func containsInput(_ input: Scheme.Trigger.Input) -> Bool {
        guard case let .button(button) = input else {
            return false
        }
        return contains(button)
    }
}
