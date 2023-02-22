// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

extension Scheme.Buttons {
    struct ClickDebouncing: Codable, Equatable, ImplicitInitable {
        var timeout: Int?
        var resetTimerOnMouseUp: Bool?
        var buttons: [CGMouseButton]?
    }
}
