// MIT License
// Copyright (c) 2021-2025 LinearMouse

extension Scheme.Buttons {
    struct ClickDebouncing: Codable, Equatable, ImplicitInitable {
        var timeout: Int?
        var resetTimerOnMouseUp: Bool?
        var buttons: [CGMouseButton]?
    }
}
