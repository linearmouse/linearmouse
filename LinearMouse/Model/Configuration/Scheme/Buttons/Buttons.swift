// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

extension Scheme {
    struct Buttons: Codable {
        var mappings: [Mapping]?

        var universalBackForward: Bool?
    }
}

extension Scheme.Buttons {
    func merge(into buttons: inout Self) {
        if let mappings = mappings, mappings.count > 0 {
            buttons.mappings = (buttons.mappings ?? []) + mappings
        }

        if let universalBackForward = universalBackForward {
            buttons.universalBackForward = universalBackForward
        }
    }

    func merge(into buttons: inout Self?) {
        if buttons == nil {
            buttons = Self()
        }

        merge(into: &buttons!)
    }
}
