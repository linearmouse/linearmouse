// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

class ControlClickTransformer: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .leftMouseDown else {
            return event
        }

        if event.flags.contains(.maskControl) {
            event.flags.remove(.maskControl)
        }

        return event
    }
}
