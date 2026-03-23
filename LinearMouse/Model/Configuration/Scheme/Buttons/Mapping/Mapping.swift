// MIT License
// Copyright (c) 2021-2026 LinearMouse

extension Scheme.Buttons {
    struct Mapping: Equatable, Hashable {
        var button: Button?
        var `repeat`: Bool?

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
            CGEventFlags([
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
            let genericFlags = ModifierState.generic(from: newValue)
            command = genericFlags.contains(.maskCommand)
            shift = genericFlags.contains(.maskShift)
            option = genericFlags.contains(.maskAlternate)
            control = genericFlags.contains(.maskControl)
        }
    }

    func match(with event: CGEvent) -> Bool {
        guard matches(modifierFlags: event.flags) else {
            return false
        }

        if let mouseButtonNumber = button?.mouseButtonNumber {
            guard [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                   .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                   .otherMouseDown, .otherMouseUp, .otherMouseDragged].contains(event.type) else {
                return false
            }

            guard let mouseButton = MouseEventView(event).mouseButton,
                  Int(mouseButton.rawValue) == mouseButtonNumber else {
                return false
            }
        } else if button?.logitechControl != nil {
            // Logitech control mappings are matched directly via handleLogitechControlEvent,
            // not through the CGEvent pipeline.
            return false
        }

        if let scroll {
            guard event.type == .scrollWheel else {
                return false
            }

            let view = ScrollWheelEventView(event)

            switch scroll {
            case .up:
                guard view.deltaY > 0 else {
                    return false
                }
            case .down:
                guard view.deltaY < 0 else {
                    return false
                }
            case .left:
                guard view.deltaX > 0 else {
                    return false
                }
            case .right:
                guard view.deltaX < 0 else {
                    return false
                }
            }
        }

        return true
    }

    func conflicted(with mapping: Self) -> Bool {
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
            var score = 0

            if let mouseButtonNumber = mapping.button?.mouseButtonNumber {
                score |= ((mouseButtonNumber & 0xFF) << 8)
            }

            if let logiButtonID = mapping.button?.logitechControl?.controlID {
                score |= ((logiButtonID & 0xFFFF) << 20)
                score |= ((mapping.button?.logitechControl?.specificityScore ?? 0) << 18)
            } else if mapping.button == nil, mapping.scroll != nil {
                score |= (1 << 16)
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
        case scroll
        case command
        case shift
        case option
        case control
        case action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        button = try container.decodeIfPresent(Button.self, forKey: .button)
            ?? container.decodeIfPresent(LogitechControlIdentity.self, forKey: .logiButton).map(Button.logitechControl)
            ?? container.decodeIfPresent(LogitechControlIdentity.self, forKey: .logitechControl)
            .map(Button.logitechControl)
        `repeat` = try container.decodeIfPresent(Bool.self, forKey: .repeat)
        scroll = try container.decodeIfPresent(ScrollDirection.self, forKey: .scroll)
        command = try container.decodeIfPresent(Bool.self, forKey: .command)
        shift = try container.decodeIfPresent(Bool.self, forKey: .shift)
        option = try container.decodeIfPresent(Bool.self, forKey: .option)
        control = try container.decodeIfPresent(Bool.self, forKey: .control)
        action = try container.decodeIfPresent(Action.self, forKey: .action)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(button, forKey: .button)
        try container.encodeIfPresent(`repeat`, forKey: .repeat)
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
