// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

class SchemeState: ObservableObject {
    private let index: Int

    @Published var reverseScrollingVertically: Bool {}

    init(of index: Int) {
        self.index = index

        let scheme = ConfigurationState.shared.configuration.schemes[index]

        reverseScrollingVertically = scheme.scrolling?.reverse?.vertical ?? false
    }
}
