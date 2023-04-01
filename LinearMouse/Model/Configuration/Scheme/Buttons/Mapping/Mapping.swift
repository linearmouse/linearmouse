// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

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
        let view = MouseEventView(event)

        if let button = button {
            guard let mouseButton = view.mouseButton,
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

        return view.modifierFlags == modifierFlags
    }
}
