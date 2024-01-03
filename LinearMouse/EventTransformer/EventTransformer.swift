// MIT License
// Copyright (c) 2021-2024 LinearMouse

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

protocol Deactivatable {
    func deactivate()
    func reactivate()
}

extension Deactivatable {
    func deactivate() {}
    func reactivate() {}
}

extension [EventTransformer]: Deactivatable {
    func deactivate() {
        for eventTransformer in self {
            if let eventTransformer = eventTransformer as? Deactivatable {
                eventTransformer.deactivate()
            }
        }
    }

    func reactivate() {
        for eventTransformer in self {
            if let eventTransformer = eventTransformer as? Deactivatable {
                eventTransformer.reactivate()
            }
        }
    }
}
