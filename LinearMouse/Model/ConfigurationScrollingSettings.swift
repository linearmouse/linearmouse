// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

struct ConfigurationScrollingSettings: Codable {
    enum Reverse: String, Codable {
        case none, vertical, horizontal, both
    }

    var reverse: Reverse?

    var distance: LinesOrPixels?
}

extension ConfigurationScrollingSettings {
    func merge(into settings: inout Self?) {
        if settings == nil {
            settings = self
            return
        }

        if let reverse = reverse {
            settings?.reverse = reverse
        }

        if let distance = distance {
            settings?.distance = distance
        }
    }
}
