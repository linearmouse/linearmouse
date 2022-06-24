// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

struct ConfigurationScrollingSettings: Codable {
    struct Reverse: Codable {
        var vertical: Bool?
        var horizontal: Bool?
    }

    var reverse: Reverse?

    var distance: LinesOrPixels?
}

extension ConfigurationScrollingSettings {
    func merge(into scrolling: inout Self?) {
        if scrolling == nil {
            scrolling = Self()
        }

        if let reverse = reverse {
            scrolling?.reverse = reverse
        }

        if let distance = distance {
            scrolling?.distance = distance
        }
    }
}
