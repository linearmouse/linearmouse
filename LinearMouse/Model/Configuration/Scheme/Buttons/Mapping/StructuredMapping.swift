// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics

extension Scheme.Buttons.Mapping {
    enum PrimaryButtonUsageRisk: Equatable {
        case standaloneLongPress
        case simultaneousChord(recommendedHeldButton: Button?)
        case heldPrefix
    }

    /// Optional collections keep the persisted schema compact and distinguish omitted fields.
    struct Trigger: Codable, Equatable, Hashable {
        struct TwoButtonRelationship: Equatable {
            enum Kind: Equatable {
                case simultaneous
                case holdThenPress
            }

            var kind: Kind
            var first: Button
            var second: Button
        }

        var input: Input
        // swiftlint:disable:next discouraged_optional_collection
        var simultaneous: [Button]?
        // swiftlint:disable:next discouraged_optional_collection
        var whileHeld: [Button]?
        // swiftlint:disable:next discouraged_optional_collection
        var modifiers: [Modifier]?

        init(
            input: Input,
            // swiftlint:disable:next discouraged_optional_collection
            simultaneous: [Button]? = nil,
            // swiftlint:disable:next discouraged_optional_collection
            whileHeld: [Button]? = nil,
            // swiftlint:disable:next discouraged_optional_collection
            modifiers: [Modifier]? = nil
        ) {
            self.input = input
            self.simultaneous = simultaneous.nilIfEmpty
            self.whileHeld = whileHeld.nilIfEmpty
            self.modifiers = modifiers.nilIfEmpty
        }

        var modifierFlags: CGEventFlags {
            get {
                CGEventFlags((modifiers ?? []).map(\.flag))
            }
            set {
                let flags = ModifierState.generic(from: newValue)
                let modifiers = Modifier.allCases.filter { flags.contains($0.flag) }
                self.modifiers = modifiers.isEmpty ? nil : modifiers
            }
        }

        var statefulButtons: Set<Button> {
            var buttons = Set(simultaneous ?? [])
            buttons.formUnion(whileHeld ?? [])
            if case let .button(button) = input {
                buttons.insert(button)
            }
            return buttons
        }

        var chordButtons: Set<Button> {
            var buttons = Set(simultaneous ?? [])
            if case let .button(button) = input {
                buttons.insert(button)
            }
            return buttons
        }

        /// A two-button relationship that can be losslessly switched between
        /// a chord and "hold, then press" without changing its outcomes.
        var twoButtonRelationship: TwoButtonRelationship? {
            guard case let .button(inputButton) = input else {
                return nil
            }

            if whileHeld == nil,
               let simultaneous,
               simultaneous.count == 1,
               let secondButton = simultaneous.first {
                return .init(
                    kind: .simultaneous,
                    first: inputButton,
                    second: secondButton
                )
            }

            if simultaneous == nil,
               let whileHeld,
               whileHeld.count == 1,
               let firstButton = whileHeld.first {
                return .init(
                    kind: .holdThenPress,
                    first: firstButton,
                    second: inputButton
                )
            }

            return nil
        }

        mutating func setTwoButtonRelationship(
            _ kind: TwoButtonRelationship.Kind,
            preferredHeldButton: Button? = nil
        ) {
            guard let relationship = twoButtonRelationship else {
                return
            }

            var firstButton = relationship.first
            var secondButton = relationship.second
            if kind == .holdThenPress,
               let preferredHeldButton,
               secondButton == preferredHeldButton {
                swap(&firstButton, &secondButton)
            }

            switch kind {
            case .simultaneous:
                input = .button(firstButton)
                simultaneous = [secondButton]
                whileHeld = nil
            case .holdThenPress:
                input = .button(secondButton)
                simultaneous = nil
                whileHeld = [firstButton]
            }
        }

        var specificityScore: Int {
            statefulButtons.count * 16 + Set(modifiers ?? []).count
        }

        var canonicalized: Self {
            .init(
                input: input,
                simultaneous: simultaneous?.uniquedAndSorted,
                whileHeld: whileHeld?.uniquedAndSorted,
                modifiers: modifiers.map { Array(Set($0)).sorted { $0.sortOrder < $1.sortOrder } }
            )
        }

        func isEquivalent(to other: Self) -> Bool {
            guard Set(modifiers ?? []) == Set(other.modifiers ?? []),
                  Set(whileHeld ?? []) == Set(other.whileHeld ?? []) else {
                return false
            }

            switch (input, other.input) {
            case (.button, .button):
                return chordButtons == other.chordButtons
            case let (.wheel(direction), .wheel(otherDirection)):
                return direction == otherDirection &&
                    (simultaneous ?? []).isEmpty &&
                    (other.simultaneous ?? []).isEmpty
            default:
                return false
            }
        }

        func valid(with outcomes: Outcomes?) -> Bool {
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

    enum TriggerInput: Equatable, Hashable {
        case button(Button)
        case wheel(ScrollDirection)
    }

    enum Modifier: String, Codable, CaseIterable, Equatable, Hashable {
        case command
        case shift
        case option
        case control

        fileprivate var flag: CGEventFlags {
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

        fileprivate var sortOrder: Int {
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

extension Scheme.Buttons.Mapping.Trigger {
    typealias Input = Scheme.Buttons.Mapping.TriggerInput
}

extension Scheme.Buttons.Mapping.TriggerInput: Codable {
    private enum CodingKeys: String, CodingKey {
        case button
        case wheel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let button = try container.decodeIfPresent(Scheme.Buttons.Mapping.Button.self, forKey: .button)
        let wheel = try container.decodeIfPresent(
            Scheme.Buttons.Mapping.ScrollDirection.self,
            forKey: .wheel
        )

        if let button, wheel == nil {
            self = .button(button)
            return
        }
        if let wheel, button == nil {
            self = .wheel(wheel)
            return
        }

        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "A trigger input must contain exactly one button or wheel direction."
        ))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .button(button):
            try container.encode(button, forKey: .button)
        case let .wheel(direction):
            try container.encode(direction, forKey: .wheel)
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

    /// Describes how an unmodified trigger can take ownership of an otherwise
    /// normal primary-button stream. An ordered trigger whose input is Primary
    /// is intentionally excluded: it cannot match until its held prefix is
    /// already down, so an ordinary Primary click remains untouched.
    var primaryButtonUsageRisk: PrimaryButtonUsageRisk? {
        guard let trigger = effectiveTrigger,
              trigger.modifierFlags.isEmpty else {
            return nil
        }

        let primaryButton = Button.mouse(0)
        let heldButtons = Set(trigger.whileHeld ?? [])
        if heldButtons.contains(primaryButton) {
            return .heldPrefix
        }

        guard heldButtons.isEmpty,
              trigger.chordButtons.contains(primaryButton) else {
            return nil
        }

        if trigger.chordButtons.count > 1 {
            let recommendedHeldButton: Button? = if let relationship = trigger.twoButtonRelationship {
                relationship.first == primaryButton ? relationship.second : relationship.first
            } else {
                nil
            }
            return .simultaneousChord(recommendedHeldButton: recommendedHeldButton)
        }

        guard outcomes?.isLongPressOnly == true else {
            return nil
        }
        return .standaloneLongPress
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

private extension Optional where Wrapped: Collection {
    var nilIfEmpty: Wrapped? {
        guard let self, !self.isEmpty else {
            return nil
        }
        return self
    }
}

private extension Array where Element == Scheme.Buttons.Mapping.Button {
    var uniquedAndSorted: Self {
        Array(Set(self)).sorted { $0.canonicalSortKey < $1.canonicalSortKey }
    }

    func containsInput(_ input: Scheme.Buttons.Mapping.Trigger.Input) -> Bool {
        guard case let .button(button) = input else {
            return false
        }
        return contains(button)
    }
}

private extension Scheme.Buttons.Mapping.Button {
    var canonicalSortKey: String {
        switch self {
        case let .mouse(number):
            return "mouse:\(number)"
        case let .logitechControl(identity):
            return "logitech:\(identity.productID ?? -1):\(identity.serialNumber ?? ""):\(identity.controlID)"
        }
    }
}
