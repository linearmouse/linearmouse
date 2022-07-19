// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

extension Scheme.Buttons {
    struct Mapping: Codable {
        var button: Int

        var command: Bool?
        var shift: Bool?
        var option: Bool?
        var control: Bool?

        var action: Action?
    }
}
