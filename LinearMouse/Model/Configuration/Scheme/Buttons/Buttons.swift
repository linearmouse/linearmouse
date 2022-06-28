// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

extension Scheme {
    struct Buttons: Codable {
        var universalBackForward: Bool?
    }
}

extension Scheme.Buttons {
    func merge(into buttons: inout Self) {
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
