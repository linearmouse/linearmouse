// MIT License
// Copyright (c) 2021-2026 LinearMouse

extension Scheme.Buttons {
    struct ClickDebouncing: Codable, Equatable, ImplicitInitable {
        static let standardButtons: [CGMouseButton] = [
            .left,
            .right,
            .center,
            .back,
            .forward
        ]

        enum Mode: String, Codable, Equatable {
            case legacy
            case libinput
        }

        var mode: Mode?
        var timeout: Int?
        var resetTimerOnMouseUp: Bool?
        var buttons: [CGMouseButton]?
    }
}

extension Scheme.Buttons.ClickDebouncing {
    func merge(into clickDebouncing: inout Self) {
        if let mode {
            clickDebouncing.mode = mode
        }

        if let timeout {
            clickDebouncing.timeout = timeout
        }

        if let resetTimerOnMouseUp {
            clickDebouncing.resetTimerOnMouseUp = resetTimerOnMouseUp
        }

        if let buttons {
            clickDebouncing.buttons = buttons
        }
    }

    func merge(into clickDebouncing: inout Self?) {
        if clickDebouncing == nil {
            clickDebouncing = Self()
        }

        merge(into: &clickDebouncing!)
    }
}
