// MIT License
// Copyright (c) 2021-2026 LinearMouse

extension Scheme.Buttons {
    struct Mapping: Equatable, Hashable {
        /// The structured trigger used by button mappings.
        ///
        /// Legacy `button`, `scroll`, and modifier fields remain decodable. Entries
        /// in `buttons.mappings` are normalized to this structured representation.
        var trigger: Trigger?
        var outcomes: Outcomes?

        var button: Button?
        var `repeat`: Bool?
        var hold: Bool?

        var scroll: ScrollDirection?

        var command: Bool?
        var shift: Bool?
        var option: Bool?
        var control: Bool?

        var action: Action?
    }
}

extension Scheme.Buttons.Mapping {
    enum Button: Equatable, Hashable {
        case mouse(Int)
        case logitechControl(LogitechControlIdentity)

        var mouseButtonNumber: Int? {
            guard case let .mouse(buttonNumber) = self else {
                return nil
            }

            return buttonNumber
        }

        var logitechControl: LogitechControlIdentity? {
            guard case let .logitechControl(identity) = self else {
                return nil
            }

            return identity
        }

        var syntheticMouseButtonNumber: Int {
            switch self {
            case let .mouse(buttonNumber):
                return buttonNumber
            case .logitechControl:
                return LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.reservedVirtualButtonNumber
            }
        }
    }

    var valid: Bool {
        if let trigger {
            guard trigger.valid(with: outcomes) else {
                return false
            }
            switch trigger.input {
            case .button:
                return outcomes?.isEmpty == false
            case .wheel:
                return action != nil
            }
        }

        guard button != nil || scroll != nil else {
            return false
        }

        guard !(button?.mouseButtonNumber == 0 && modifierFlags.isEmpty) else {
            return false
        }

        return true
    }

    enum ScrollDirection: String, Codable, Hashable {
        case up, down, left, right
    }

    var modifierFlags: CGEventFlags {
        get {
            if let trigger {
                return trigger.modifierFlags
            }

            return CGEventFlags(
                [
                    (command, CGEventFlags.maskCommand),
                    (shift, CGEventFlags.maskShift),
                    (option, CGEventFlags.maskAlternate),
                    (control, CGEventFlags.maskControl)
                ]
                .filter { $0.0 == true }
                .map(\.1)
            )
        }

        set {
            if trigger != nil {
                trigger?.modifierFlags = newValue
                return
            }

            let genericFlags = ModifierState.generic(from: newValue)
            command = genericFlags.contains(.maskCommand)
            shift = genericFlags.contains(.maskShift)
            option = genericFlags.contains(.maskAlternate)
            control = genericFlags.contains(.maskControl)
        }
    }

    func conflicted(with mapping: Self) -> Bool {
        if trigger != nil || mapping.trigger != nil {
            guard let trigger = effectiveTrigger,
                  let otherTrigger = mapping.effectiveTrigger,
                  trigger.isEquivalent(to: otherTrigger) else {
                return false
            }

            var lhs = self
            var rhs = mapping
            lhs.normalizeAsStructured()
            rhs.normalizeAsStructured()
            return lhs.hasOverlappingOutcome(with: rhs)
        }

        guard scroll == mapping.scroll,
              conflicts(withModifierFlagsOf: mapping) else {
            return false
        }

        return button == mapping.button
    }

    func matches(modifierFlags eventFlags: CGEventFlags) -> Bool {
        ModifierState.generic(from: eventFlags) == modifierFlags
    }

    private func conflicts(withModifierFlagsOf mapping: Self) -> Bool {
        modifierFlags == mapping.modifierFlags
    }
}

extension Scheme.Buttons.Mapping: Comparable {
    static func < (lhs: Scheme.Buttons.Mapping, rhs: Scheme.Buttons.Mapping) -> Bool {
        func score(_ mapping: Scheme.Buttons.Mapping) -> Int {
            let triggerButton: Scheme.Buttons.Mapping.Button?
            let scrollDirection: Scheme.Buttons.Mapping.ScrollDirection?

            switch mapping.trigger?.input {
            case let .button(button):
                triggerButton = button
                scrollDirection = nil
            case let .wheel(direction):
                triggerButton = nil
                scrollDirection = direction
            case nil:
                triggerButton = mapping.button
                scrollDirection = mapping.scroll
            }

            var score: Int
            if let mouseButtonNumber = triggerButton?.mouseButtonNumber {
                score = (mouseButtonNumber & 0xFFFF) << 32
            } else if let scrollDirection {
                let directionOrder: Int
                switch scrollDirection {
                case .up:
                    directionOrder = 0
                case .down:
                    directionOrder = 1
                case .left:
                    directionOrder = 2
                case .right:
                    directionOrder = 3
                }
                score = (1 << 56) | (directionOrder << 32)
            } else if let logitechControl = triggerButton?.logitechControl {
                score = (2 << 56) |
                    ((logitechControl.controlID & 0xFFFF) << 32) |
                    ((logitechControl.specificityScore & 0xFFFF) << 16)
            } else {
                score = 3 << 56
            }

            if let trigger = mapping.trigger {
                score |= (trigger.specificityScore & 0xFFF) << 4
            }

            if mapping.modifierFlags.contains(.maskCommand) {
                score |= (1 << 0)
            }
            if mapping.modifierFlags.contains(.maskShift) {
                score |= (1 << 1)
            }
            if mapping.modifierFlags.contains(.maskAlternate) {
                score |= (1 << 2)
            }
            if mapping.modifierFlags.contains(.maskControl) {
                score |= (1 << 3)
            }

            return score
        }

        return score(lhs) < score(rhs)
    }
}

extension Scheme.Buttons.Mapping: Codable {
    private enum CodingKeys: String, CodingKey {
        case button
        case logiButton
        case logitechControl
        case `repeat`
        case hold
        case scroll
        case command
        case shift
        case option
        case control
        case action
        case trigger
        case outcomes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        trigger = try container.decodeIfPresent(Trigger.self, forKey: .trigger)
        outcomes = try container.decodeIfPresent(Outcomes.self, forKey: .outcomes)
        button = try container.decodeIfPresent(Button.self, forKey: .button)
            ?? container.decodeIfPresent(LogitechControlIdentity.self, forKey: .logiButton).map(Button.logitechControl)
            ?? container.decodeIfPresent(LogitechControlIdentity.self, forKey: .logitechControl)
            .map(Button.logitechControl)
        `repeat` = try container.decodeIfPresent(Bool.self, forKey: .repeat)
        hold = try container.decodeIfPresent(Bool.self, forKey: .hold)
        scroll = try container.decodeIfPresent(ScrollDirection.self, forKey: .scroll)
        command = try container.decodeIfPresent(Bool.self, forKey: .command)
        shift = try container.decodeIfPresent(Bool.self, forKey: .shift)
        option = try container.decodeIfPresent(Bool.self, forKey: .option)
        control = try container.decodeIfPresent(Bool.self, forKey: .control)
        action = try container.decodeIfPresent(Action.self, forKey: .action)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(trigger, forKey: .trigger)
        try container.encodeIfPresent(outcomes, forKey: .outcomes)
        try container.encodeIfPresent(button, forKey: .button)
        try container.encodeIfPresent(`repeat`, forKey: .repeat)
        try container.encodeIfPresent(hold, forKey: .hold)
        try container.encodeIfPresent(scroll, forKey: .scroll)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(shift, forKey: .shift)
        try container.encodeIfPresent(option, forKey: .option)
        try container.encodeIfPresent(control, forKey: .control)
        try container.encodeIfPresent(action, forKey: .action)
    }
}

extension Scheme.Buttons.Mapping.Button: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
    }

    private enum Kind: String, Codable {
        case logitechControl
    }

    init(from decoder: Decoder) throws {
        if let buttonNumber = try? decoder.singleValueContainer().decode(Int.self) {
            self = .mouse(buttonNumber)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .logitechControl:
            self = try .logitechControl(LogitechControlIdentity(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .mouse(buttonNumber):
            var container = encoder.singleValueContainer()
            try container.encode(buttonNumber)
        case let .logitechControl(identity):
            try identity.encode(to: encoder)
        }
    }
}
