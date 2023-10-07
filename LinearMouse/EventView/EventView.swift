// MIT License
// Copyright (c) 2021-2023 LinearMouse

class EventView {
    let event: CGEvent

    init(_ event: CGEvent) {
        self.event = event
    }

    var modifierFlags: CGEventFlags {
        get {
            event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        }
        set {
            event.flags = event.flags
                .subtracting([.maskCommand, .maskShift, .maskAlternate, .maskControl])
                .union(newValue)
        }
    }

    var modifiers: [String] {
        [
            (CGEventFlags.maskCommand, "command"),
            (CGEventFlags.maskShift, "shift"),
            (CGEventFlags.maskAlternate, "option"),
            (CGEventFlags.maskControl, "control")
        ]
        .filter { modifierFlags.contains($0.0) }
        .map(\.1)
    }
}
