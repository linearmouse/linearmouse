// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

extension Scheme.Buttons {
    // TODO: TBD.
    struct Binding: Codable {
        var button: Int
        var shift: Bool?
        var control: Bool?
        var option: Bool?
        var command: Bool?
    }
}
