// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

extension Scheme.Scrolling {
    struct Modifiers: Codable {
        var command: Action?
        var shift: Action?
        var option: Action?
        var control: Action?
    }
}

extension Scheme.Scrolling.Modifiers {
    enum Action: Codable {
        case alterOrientation
        case changeSpeed(Double)
    }
}

extension Scheme.Scrolling.Modifiers {
    func merge(into modifiers: inout Self) {
        if let command = command {
            modifiers.command = command
        }

        if let shift = shift {
            modifiers.shift = shift
        }

        if let option = option {
            modifiers.option = option
        }

        if let control = control {
            modifiers.control = control
        }
    }

    func merge(into modifiers: inout Self?) {
        if modifiers == nil {
            modifiers = Self()
        }

        merge(into: &modifiers!)
    }
}
