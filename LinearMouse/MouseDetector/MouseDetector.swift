// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation

protocol MouseDetector {
    func isMouseEvent(_ event: CGEvent) -> Bool
}
