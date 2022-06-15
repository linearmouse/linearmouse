// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

class DefaultMouseDetector: MouseDetector {
    func isMouseEvent(_: CGEvent) -> Bool {
        DeviceManager.shared.lastActiveDevice?.category == .mouse
    }
}
