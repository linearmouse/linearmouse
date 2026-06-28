// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import LRUCache
import os.log

struct EventTransformerContext {
    var device: Device?
}

struct EventTransformerResolution {
    var transformer: EventTransformer
    var context: EventTransformerContext

    func transform(_ event: CGEvent) -> CGEvent? {
        transformer.transform(event, in: context)
    }
}

protocol EventTransformer {
    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent?
}

enum LogitechControlEventHandlingResult {
    case notHandled
    case handled
    case handledAllowingSyntheticFallback
    case handledDeferringSyntheticFallback

    var suppressesSyntheticFallback: Bool {
        self == .handled || self == .handledDeferringSyntheticFallback
    }
}

protocol LogitechControlEventHandling {
    func handleLogitechControlEvent(_ context: LogitechEventContext) -> LogitechControlEventHandlingResult
}

extension [EventTransformer]: EventTransformer {
    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        var event: CGEvent? = event

        for eventTransformer in self {
            event = event.flatMap { eventTransformer.transform($0, in: context) }
        }

        return event
    }
}

extension [EventTransformer]: LogitechControlEventHandling {
    func handleLogitechControlEvent(_ context: LogitechEventContext) -> LogitechControlEventHandlingResult {
        for eventTransformer in self {
            let result = (eventTransformer as? LogitechControlEventHandling)?.handleLogitechControlEvent(context)
                ?? .notHandled
            if result != .notHandled {
                return result
            }
        }

        return .notHandled
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
