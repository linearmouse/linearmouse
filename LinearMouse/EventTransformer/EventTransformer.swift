// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Foundation
import LRUCache
import os.log

protocol EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent?
}

extension [EventTransformer]: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        var event: CGEvent? = event

        for eventTransformer in self {
            event = event.flatMap { eventTransformer.transform($0) }
        }

        return event
    }
}
