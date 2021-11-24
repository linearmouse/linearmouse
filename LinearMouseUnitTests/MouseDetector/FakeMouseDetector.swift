//
//  FakeMouseDetector.swift
//  LinearMouseUnitTests
//
//  Created by lujjjh on 2021/11/20.
//

import Foundation
@testable import LinearMouse

class FakeMouseDetector: MouseDetector {
    let isMouse: Bool

    init(isMouse: Bool) {
        self.isMouse = isMouse
    }

    func isMouseEvent(_ event: CGEvent) -> Bool {
        return isMouse
    }
}
