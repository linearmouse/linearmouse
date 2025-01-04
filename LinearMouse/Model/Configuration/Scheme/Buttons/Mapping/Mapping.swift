// MIT License
// Copyright (c) 2021-2025 LinearMouse

extension Scheme.Buttons {
    struct Mapping: Codable, Equatable, Hashable {
        var button: Int?
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
    var valid: Bool {
        guard button != nil || scroll != nil else {
            return false
        }

        guard !(button == 0 && modifierFlags.isEmpty) else {
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
            .map(\.1))
        }

        set {
            command = newValue.contains(.maskCommand)
            shift = newValue.contains(.maskShift)
            option = newValue.contains(.maskAlternate)
            control = newValue.contains(.maskControl)
        }
    }

    func match(with event: CGEvent) -> Bool {
        let view = EventView(event)

        guard view.modifierFlags == modifierFlags else {
            return false
        }

        if let button = button {
            guard [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                   .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                   .otherMouseDown, .otherMouseUp, .otherMouseDragged].contains(event.type) else {
                return false
            }

            guard let mouseButton = MouseEventView(event).mouseButton,
                  mouseButton.rawValue == button else {
                return false
            }
        }

        if let scroll = scroll {
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
        if button == mapping.button, scroll == mapping.scroll, modifierFlags == mapping.modifierFlags {
            return true
        }
        return false
    }
}

extension Scheme.Buttons.Mapping: Comparable {
    static func < (lhs: Scheme.Buttons.Mapping, rhs: Scheme.Buttons.Mapping) -> Bool {
        func score(_ mapping: Scheme.Buttons.Mapping) -> Int {
            var score = 0

            if let button = mapping.button {
                score |= ((button & 0xFF) << 8)
            } else if mapping.scroll != nil {
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
