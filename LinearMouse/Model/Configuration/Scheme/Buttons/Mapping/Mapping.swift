// MIT License
// Copyright (c) 2021-2026 LinearMouse

extension Scheme.Buttons {
    struct Mapping: Equatable, Hashable {
        var button: Int?
        var logiButton: LogitechControlIdentity?
        var `repeat`: Bool?

        var scroll: ScrollDirection?

        var modifierFlagsRaw: UInt64?
        var command: Bool?
        var shift: Bool?
        var option: Bool?
        var control: Bool?

        var action: Action?
    }
}

extension Scheme.Buttons.Mapping {
    var valid: Bool {
        guard button != nil || logiButton != nil || scroll != nil else {
            return false
        }

        guard !(button == 0 && logiButton == nil && modifierFlags.isEmpty) else {
            return false
        }

        return true
    }

    enum ScrollDirection: String, Codable, Hashable {
        case up, down, left, right
    }

    var modifierFlags: CGEventFlags {
        get {
            if let modifierFlagsRaw {
                return ModifierState.generic(from: CGEventFlags(rawValue: modifierFlagsRaw))
            }

            return CGEventFlags([
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
            let normalizedFlags = ModifierState.normalize(newValue)
            let sideSpecificFlags = ModifierState.sideSpecific(from: normalizedFlags)
            modifierFlagsRaw = sideSpecificFlags.isEmpty ? nil : normalizedFlags.rawValue

            let genericFlags = ModifierState.generic(from: normalizedFlags)
            command = genericFlags.contains(.maskCommand)
            shift = genericFlags.contains(.maskShift)
            option = genericFlags.contains(.maskAlternate)
            control = genericFlags.contains(.maskControl)
        }
    }

    var rawModifierFlags: CGEventFlags {
        get {
            if let modifierFlagsRaw {
                return ModifierState.normalize(CGEventFlags(rawValue: modifierFlagsRaw))
            }

            return ModifierState.generic(from: modifierFlags)
        }

        set {
            modifierFlags = newValue
        }
    }

    func match(with event: CGEvent) -> Bool {
        guard matches(modifierFlags: event.flags) else {
            return false
        }

        if let button {
            guard [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                   .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                   .otherMouseDown, .otherMouseUp, .otherMouseDragged].contains(event.type) else {
                return false
            }

            guard let mouseButton = MouseEventView(event).mouseButton,
                  mouseButton.rawValue == button else {
                return false
            }
        } else if logiButton != nil {
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

        if let logiButton, let otherLogiButton = mapping.logiButton {
            return logiButton == otherLogiButton
        }

        return button == mapping.button && logiButton == mapping.logiButton
    }

    func matches(modifierFlags eventFlags: CGEventFlags) -> Bool {
        let normalizedFlags = ModifierState.normalize(eventFlags)

        if let modifierFlagsRaw {
            return normalizedFlags == ModifierState.normalize(CGEventFlags(rawValue: modifierFlagsRaw))
        }

        return ModifierState.generic(from: normalizedFlags) == modifierFlags
    }

    private func conflicts(withModifierFlagsOf mapping: Self) -> Bool {
        switch (modifierFlagsRaw, mapping.modifierFlagsRaw) {
        case let (lhsRaw?, rhsRaw?):
            return ModifierState.normalize(CGEventFlags(rawValue: lhsRaw)) == ModifierState
                .normalize(CGEventFlags(rawValue: rhsRaw))
        case (_?, nil):
            return mapping.matches(modifierFlags: rawModifierFlags)
        case (nil, _?):
            return matches(modifierFlags: mapping.rawModifierFlags)
        case (nil, nil):
            return modifierFlags == mapping.modifierFlags
        }
    }
}

extension Scheme.Buttons.Mapping: Comparable {
    static func < (lhs: Scheme.Buttons.Mapping, rhs: Scheme.Buttons.Mapping) -> Bool {
        func score(_ mapping: Scheme.Buttons.Mapping) -> Int {
            var score = 0

            if let button = mapping.button {
                score |= ((button & 0xFF) << 8)
            }

            if let logiButtonID = mapping.logiButton?.controlID {
                score |= ((logiButtonID & 0xFFFF) << 20)
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

            score |= Int(truncatingIfNeeded: ModifierState.sideSpecific(from: mapping.rawModifierFlags).rawValue >> 4) &
                0xF0

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
        case modifierFlagsRaw
        case command
        case shift
        case option
        case control
        case action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        button = try container.decodeIfPresent(Int.self, forKey: .button)
        logiButton = try container.decodeIfPresent(LogitechControlIdentity.self, forKey: .logiButton)
            ?? container.decodeIfPresent(LogitechControlIdentity.self, forKey: .logitechControl)
        `repeat` = try container.decodeIfPresent(Bool.self, forKey: .repeat)
        scroll = try container.decodeIfPresent(ScrollDirection.self, forKey: .scroll)
        modifierFlagsRaw = try container.decodeIfPresent(UInt64.self, forKey: .modifierFlagsRaw)
        command = try container.decodeIfPresent(Bool.self, forKey: .command)
        shift = try container.decodeIfPresent(Bool.self, forKey: .shift)
        option = try container.decodeIfPresent(Bool.self, forKey: .option)
        control = try container.decodeIfPresent(Bool.self, forKey: .control)

        action = try container.decodeIfPresent(Action.self, forKey: .action)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(button, forKey: .button)
        try container.encodeIfPresent(logiButton, forKey: .logiButton)
        try container.encodeIfPresent(`repeat`, forKey: .repeat)
        try container.encodeIfPresent(scroll, forKey: .scroll)
        try container.encodeIfPresent(modifierFlagsRaw, forKey: .modifierFlagsRaw)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(shift, forKey: .shift)
        try container.encodeIfPresent(option, forKey: .option)
        try container.encodeIfPresent(control, forKey: .control)
        try container.encodeIfPresent(action, forKey: .action)
    }
}
