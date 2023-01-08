// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

extension Scheme.Buttons {
    struct Mapping: Codable {
        var button: Int

        var command: Bool?
        var shift: Bool?
        var option: Bool?
        var control: Bool?

        var action: Action?

        var `repeat`: Bool?
    }
}

extension Scheme.Buttons.Mapping {
    var modifierFlags: CGEventFlags {
        CGEventFlags([
            (command, CGEventFlags.maskCommand),
            (shift, CGEventFlags.maskShift),
            (option, CGEventFlags.maskAlternate),
            (control, CGEventFlags.maskControl)
        ]
        .filter { $0.0 == true }
        .map(\.1))
    }

    func match(with event: CGEvent) -> Bool {
        let view = MouseEventView(event)

        guard let mouseButton = view.mouseButton, mouseButton.rawValue == button else {
            return false
        }

        return view.modifierFlags == modifierFlags
    }
}
