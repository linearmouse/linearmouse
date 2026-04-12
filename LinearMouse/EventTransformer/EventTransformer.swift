// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import LRUCache
import os.log

protocol EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent?
}

protocol LogitechControlEventHandling {
    func handleLogitechControlEvent(_ context: LogitechEventContext) -> Bool
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

extension [EventTransformer]: LogitechControlEventHandling {
    func handleLogitechControlEvent(_ context: LogitechEventContext) -> Bool {
        contains { eventTransformer in
            (eventTransformer as? LogitechControlEventHandling)?.handleLogitechControlEvent(context) == true
        }
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
