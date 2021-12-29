//
//  Extensions.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/1/28.
//

import Foundation

class Extensions: EventTransformer {
    let extensions: [Extension]

    init(extensions: [Extension]) {
        self.extensions = extensions
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        for `extension` in extensions {
            `extension`
        }
    }
}
