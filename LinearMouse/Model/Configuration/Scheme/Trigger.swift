// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics

extension Scheme {
    /// The input that activates a feature: a button or wheel direction, optionally
    /// combined with held buttons and keyboard modifiers.
    ///
    /// Button mappings use every field. Other features may accept only a subset.
    /// Optional collections keep the persisted schema compact and distinguish omitted fields.
    struct Trigger: Codable, Equatable, Hashable {
        typealias Button = Scheme.Buttons.Mapping.Button
        typealias Modifier = Scheme.Buttons.Mapping.Modifier
        typealias ScrollDirection = Scheme.Buttons.Mapping.ScrollDirection

        enum Input: Equatable, Hashable {
            case button(Button)
            case wheel(ScrollDirection)
        }

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
    }
}

extension Scheme.Trigger.Input: Codable {
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

private extension Optional where Wrapped: Collection {
    var nilIfEmpty: Wrapped? {
        guard let self, !self.isEmpty else {
            return nil
        }
        return self
    }
}

private extension Array where Element == Scheme.Trigger.Button {
    var uniquedAndSorted: Self {
        Array(Set(self)).sorted { $0.canonicalSortKey < $1.canonicalSortKey }
    }
}

private extension Scheme.Trigger.Button {
    var canonicalSortKey: String {
        switch self {
        case let .mouse(number):
            return "mouse:\(number)"
        case let .logitechControl(identity):
            return "logitech:\(identity.productID ?? -1):\(identity.serialNumber ?? ""):\(identity.controlID)"
        }
    }
}
